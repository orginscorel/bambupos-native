<?php

namespace App\Modules\Kds\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Kds\Support\KdsPresenter;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderEvent;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Services\TableStatusSynchronizer;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * KDS okuma modelleri + mutfak eylemleri (Faz-4).
 *
 * SINIR: Orders modülü DEĞİŞTİRİLMEZ. Kalem durum ilerletme OrderService'in
 * hazır uçlarına delege edilir (transaction + kilit + sürüm + türetme orada).
 * OrderService'te KARŞILIĞI OLMAYAN üç mutfak eylemi (geri alma, istasyon
 * transferi, komi teslim işareti) OrderService::withLockedOrder çekirdeği
 * üzerinden burada uygulanır ve order_events'e loglanır; bunların
 * OrderService'e taşınması koordinasyon notu olarak raporlanmıştır.
 */
class KdsService
{
    /** Mutfak ekranının gördüğü sipariş durumları (kalemi bitmemiş aşamalar). */
    private const KITCHEN_ORDER_STATUSES = [
        'placed', 'sent_to_station', 'accepted', 'preparing',
        'partially_ready', 'ready', 'awaiting_service',
    ];

    /** Mutfak kartında görünen kalem durumları (served/cancelled hariç). */
    private const KITCHEN_ITEM_STATUSES = [
        'placed', 'sent_to_station', 'accepted', 'preparing', 'ready',
    ];

    public function __construct(
        private readonly OrderService $orders,
        private readonly TableStatusSynchronizer $tables,
        private readonly StationRegistry $stations,
        private readonly KdsPresenter $presenter,
    ) {
    }

    /* =========================================================
     |  İstasyon yetki kapsamı
     * ========================================================= */

    /**
     * Kullanıcının istasyon ataması: atama VARSA yalnız o istasyonlar
     * görülür/işaretlenir (sunucu tarafında zorlanır); atama yoksa null
     * (= tüm istasyonlar).
     *
     * @return array<int, string>|null
     */
    public function allowedStations(User $user): ?array
    {
        $keys = UserStation::query()
            ->where('user_id', $user->getKey())
            ->pluck('station_key')
            ->all();

        return $keys === [] ? null : $keys;
    }

    /**
     * İstenen süzgeç + kullanıcı ataması → etkin istasyon listesi.
     * null = tümü. Atama dışı istasyon istenirse 403.
     *
     * @return array<int, string>|null
     */
    public function effectiveStations(User $user, ?string $requested): ?array
    {
        $allowed = $this->allowedStations($user);

        if ($requested === null || $requested === '' || $requested === 'all') {
            return $allowed;
        }

        if ($allowed !== null && ! in_array($requested, $allowed, true)) {
            throw new AccessDeniedHttpException('Bu istasyon size atanmamış.');
        }

        return [$requested];
    }

    /** Kalem, kullanıcının istasyon kapsamında mı (mutfak eylemleri için)? */
    private function assertItemInScope(User $user, OrderItem $item): void
    {
        $allowed = $this->allowedStations($user);

        if ($allowed !== null && ! in_array((string) $item->station, $allowed, true)) {
            throw new AccessDeniedHttpException('Bu kalem sizin istasyonunuza ait değil.');
        }
    }

    /* =========================================================
     |  Polling cursor'ı (ADR-006) — en ucuz sorgu
     * ========================================================= */

    /** Şubedeki (0 = tüm şubeler) son sipariş olayının id'si. */
    public function cursor(int $branchId): int
    {
        return (int) OrderEvent::query()
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->max('id');
    }

    /* =========================================================
     |  Okuma modelleri
     * ========================================================= */

    /**
     * Mutfak/bar kuyruğu: istasyon süzgeçli sipariş kartları.
     *
     * @return array<string, mixed>
     */
    public function kitchenQueue(User $user, int $branchId, ?string $station): array
    {
        $effective = $this->effectiveStations($user, $station);

        $orders = Order::query()
            ->with([
                'table:id,name,number,area_id', 'table.area:id,name',
                'openedBy:id,name',
                'items' => fn ($q) => $q->orderBy('id'),
                'items.options',
                'items.product:id,prep_minutes',
                'items.product.allergens:id,name,kind,icon,color',
            ])
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->whereIn('status', self::KITCHEN_ORDER_STATUSES)
            ->orderBy('id')
            ->get();

        $unassigned = (string) config('kds.unassigned_key', '_none');

        $matches = function (OrderItem $item) use ($effective, $unassigned): bool {
            if (! in_array($item->status, self::KITCHEN_ITEM_STATUSES, true)) {
                return false;
            }

            if ($effective === null) {
                return true;
            }

            $key = $item->station ?? $unassigned;

            return in_array($key, $effective, true) || in_array($item->station, $effective, true);
        };

        $visibleItemIds = $orders->flatMap(
            fn (Order $o) => $o->items->filter($matches)->pluck('id')
        );

        $pickups = $this->pickupsFor($visibleItemIds);

        $cards = $orders
            ->map(function (Order $o) use ($matches, $pickups): ?array {
                $visible = $o->items->filter($matches);

                return $visible->isEmpty() ? null : $this->presenter->orderCard($o, $visible, $pickups);
            })
            ->filter()
            ->values()
            ->all();

        return [
            'orders' => $cards,
            'summary' => $this->stationSummary($branchId, $this->allowedStations($user)),
            'cursor' => $this->cursor($branchId),
            'server_time' => now()->toIso8601String(),
        ];
    }

    /**
     * Komi kuyruğu: HAZIR kalemler (tüm istasyonlar) + teslim işaretleri.
     *
     * @return array<string, mixed>
     */
    public function runnerQueue(User $user, int $branchId): array
    {
        $orders = Order::query()
            ->with([
                'table:id,name,number,area_id', 'table.area:id,name',
                'openedBy:id,name',
                'items' => fn ($q) => $q->where('status', OrderItemStatus::Ready->value)->orderBy('updated_at'),
                'items.options',
                'items.product:id,prep_minutes',
                'items.product.allergens:id,name,kind,icon,color',
            ])
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->whereIn('status', self::KITCHEN_ORDER_STATUSES)
            ->orderBy('id')
            ->get();

        $itemIds = $orders->flatMap(fn (Order $o) => $o->items->pluck('id'));
        $pickups = $this->pickupsFor($itemIds);

        $rows = $orders
            ->flatMap(fn (Order $o) => $o->items->map(
                fn (OrderItem $i): array => $this->presenter->runnerRow($i, $o, $pickups[$i->id] ?? null)
            ))
            ->sortBy('updated_at')
            ->values()
            ->all();

        return [
            'items' => $rows,
            'cursor' => $this->cursor($branchId),
            'server_time' => now()->toIso8601String(),
        ];
    }

    /**
     * Yoğunluk özeti: istasyon başına bekleyen kalem sayısı (tek grouped
     * sorgu). Kullanıcının istasyon ataması varsa onunla sınırlanır.
     *
     * @param  array<int, string>|null  $allowed
     * @return array<int, array{station: string|null, station_label: string, pending: int}>
     */
    private function stationSummary(int $branchId, ?array $allowed): array
    {
        $rows = OrderItem::query()
            ->whereIn('order_items.status', self::KITCHEN_ITEM_STATUSES)
            ->whereHas('order', fn ($q) => $q
                ->when($branchId > 0, fn ($qq) => $qq->where('branch_id', $branchId))
                ->whereIn('status', self::KITCHEN_ORDER_STATUSES))
            ->when($allowed !== null, fn ($q) => $q->whereIn('station', $allowed))
            ->selectRaw('station, COUNT(*) as pending')
            ->groupBy('station')
            ->get();

        return $rows->map(fn ($r): array => [
            'station' => $r->station,
            'station_label' => $this->stations->labelFor($r->station) ?? 'İstasyonsuz',
            'pending' => (int) $r->pending,
        ])->values()->all();
    }

    /** @param  \Illuminate\Support\Collection<int, int|string>  $itemIds */
    private function pickupsFor(Collection $itemIds): Collection
    {
        if ($itemIds->isEmpty()) {
            return collect();
        }

        return ItemPickup::query()
            ->with('user:id,name')
            ->whereIn('order_item_id', $itemIds->all())
            ->get()
            ->keyBy('order_item_id');
    }

    /* =========================================================
     |  Mutfak eylemleri
     * ========================================================= */

    /**
     * Kalem durum ilerletme (kabul/hazırlanıyor/hazır/servis) —
     * OrderService'e delege: kilit + sürüm (409) + türetme orada.
     */
    public function advanceItem(User $user, OrderItem $item, OrderItemStatus $to, ?int $expectedVersion): OrderItem
    {
        if (! in_array($to, [OrderItemStatus::Accepted, OrderItemStatus::Preparing, OrderItemStatus::Ready, OrderItemStatus::Served], true)) {
            throw ValidationException::withMessages(['to' => ['KDS bu duruma geçiremez.']]);
        }

        if ($to !== OrderItemStatus::Served) {
            $this->assertItemInScope($user, $item);
        }

        return $this->orders->setItemStatus($item->order, $item, $to, $user, $expectedVersion);
    }

    /**
     * Siparişin (bu istasyondaki) TÜM bekleyen kalemlerini "hazır" yap.
     * Sürüm ilk adımda doğrulanır (409); kalemler OrderService üzerinden
     * tek tek ilerletilir (türetme her adımda tutarlı kalır).
     */
    public function markStationReady(User $user, Order $order, ?string $station, ?int $expectedVersion): Order
    {
        $effective = $this->effectiveStations($user, $station);
        $unassigned = (string) config('kds.unassigned_key', '_none');

        $order->refresh();

        if ($expectedVersion !== null && (int) $order->version !== $expectedVersion) {
            throw new HttpException(409, sprintf(
                'Sipariş bu sırada değişti (sürüm %d → %d). Ekran tazelendi.',
                $expectedVersion, (int) $order->version,
            ));
        }

        $pending = $order->items()
            ->whereIn('status', ['placed', 'sent_to_station', 'accepted', 'preparing'])
            ->get()
            ->filter(function (OrderItem $i) use ($effective, $unassigned): bool {
                if ($effective === null) {
                    return true;
                }

                return in_array($i->station ?? $unassigned, $effective, true);
            });

        if ($pending->isEmpty()) {
            throw ValidationException::withMessages(['order' => ['Bu istasyonda bekleyen kalem yok.']]);
        }

        foreach ($pending as $item) {
            $this->orders->setItemStatus($order, $item, OrderItemStatus::Ready, $user, null);
        }

        return $order->refresh();
    }

    /**
     * YANLIŞLIKLA işaretlemeyi geri al: ready→preparing (mutfak) ve
     * served→ready (komi). Kalem makinesi yalnız-ileri olduğundan bu
     * kontrollü geri adım KDS'de yaşar; kilit/sürüm OrderService
     * çekirdeğiyle (withLockedOrder) alınır, olay loglanır, sipariş durumu
     * kalemlerden yeniden türetilir.
     */
    public function undoItem(User $user, OrderItem $item, ?int $expectedVersion): OrderItem
    {
        return $this->orders->withLockedOrder($item->order, $expectedVersion, function (Order $locked) use ($user, $item): OrderItem {
            /** @var OrderItem $fresh */
            $fresh = $locked->items()->whereKey($item->getKey())->firstOrFail();
            $from = $fresh->statusEnum();

            $to = match ($from) {
                OrderItemStatus::Ready => OrderItemStatus::Preparing,
                OrderItemStatus::Served => OrderItemStatus::Ready,
                default => throw ValidationException::withMessages([
                    'item' => ['Yalnız "Hazır" veya "Servis edildi" işareti geri alınabilir.'],
                ]),
            };

            if ($from === OrderItemStatus::Ready) {
                $this->assertItemInScope($user, $fresh);
            }

            $fresh->status = $to->value;
            $fresh->save();

            $this->logKdsEvent($locked, 'kds_status_undone', $user, [
                'name' => $fresh->name,
            ], $from->value, $to->value, $fresh);

            $this->rederiveOrderStatus($locked, $user);

            return $fresh;
        });
    }

    /**
     * İstasyon transferi: kalem başka istasyonun kuyruğuna taşınır
     * (hazırlanmadan önce). Snapshot'taki station güncellenir, iz sürülür.
     */
    public function transferItem(User $user, OrderItem $item, string $stationKey, ?int $expectedVersion): OrderItem
    {
        if (! $this->stations->isValid($stationKey)) {
            throw ValidationException::withMessages(['station' => ['Geçersiz istasyon.']]);
        }

        $this->assertItemInScope($user, $item);

        return $this->orders->withLockedOrder($item->order, $expectedVersion, function (Order $locked) use ($user, $item, $stationKey): OrderItem {
            /** @var OrderItem $fresh */
            $fresh = $locked->items()->whereKey($item->getKey())->firstOrFail();

            if (! in_array($fresh->statusEnum(), [OrderItemStatus::Placed, OrderItemStatus::SentToStation, OrderItemStatus::Accepted, OrderItemStatus::Preparing], true)) {
                throw ValidationException::withMessages(['item' => ['Hazır/servis edilmiş kalem transfer edilemez.']]);
            }

            if ($fresh->station === $stationKey) {
                throw ValidationException::withMessages(['station' => ['Kalem zaten bu istasyonda.']]);
            }

            $from = $fresh->station;
            $fresh->station = $stationKey;
            $fresh->save();

            $this->logKdsEvent($locked, 'kds_station_transferred', $user, [
                'name' => $fresh->name,
                'from_station' => $from,
                'to_station' => $stationKey,
            ], null, null, $fresh);

            return $fresh;
        });
    }

    /* =========================================================
     |  Komi eylemleri (teslim aldım / geri al)
     * ========================================================= */

    public function pickup(User $user, OrderItem $item): ItemPickup
    {
        if ($item->statusEnum() !== OrderItemStatus::Ready) {
            throw ValidationException::withMessages(['item' => ['Yalnız "Hazır" kalem teslim alınabilir.']]);
        }

        $pickup = ItemPickup::query()->firstOrCreate(
            ['order_item_id' => $item->getKey()],
            ['user_id' => $user->getKey()],
        );

        if ($pickup->wasRecentlyCreated) {
            $this->logKdsEvent($item->order, 'kds_picked_up', $user, ['name' => $item->name], null, null, $item);
        }

        return $pickup->load('user:id,name');
    }

    public function undoPickup(User $user, OrderItem $item): void
    {
        $deleted = ItemPickup::query()->where('order_item_id', $item->getKey())->delete();

        if ($deleted > 0) {
            $this->logKdsEvent($item->order, 'kds_pickup_undone', $user, ['name' => $item->name], null, null, $item);
        }
    }

    /* =========================================================
     |  Yardımcılar
     * ========================================================= */

    /**
     * Sipariş durumunu kalemlerden yeniden türet (geri alma sonrası).
     *
     * NOT: Eşleme OrderService::deriveFromItemStatuses'ın AYNASIDIR —
     * Orders değiştirilemediği için burada tekrarlanır; Orders'a public
     * bir türetme ucu eklendiğinde bu kopya silinmelidir (rapor edildi).
     */
    private function rederiveOrderStatus(Order $order, ?User $actor): void
    {
        $current = $order->statusEnum();

        if (! $current->isKitchenPhase()) {
            return;
        }

        $statuses = $order->items()->get()
            ->filter(fn (OrderItem $i): bool => $i->isActive())
            ->map(fn (OrderItem $i): OrderItemStatus => $i->statusEnum());

        if ($statuses->isEmpty()) {
            return;
        }

        $all = fn (OrderItemStatus ...$set): bool => $statuses->every(fn ($s) => in_array($s, $set, true));
        $any = fn (OrderItemStatus ...$set): bool => $statuses->contains(fn ($s) => in_array($s, $set, true));

        $derived = match (true) {
            $all(OrderItemStatus::Served) => OrderStatus::Served,
            $all(OrderItemStatus::Ready, OrderItemStatus::Served) => OrderStatus::Ready,
            $any(OrderItemStatus::Ready, OrderItemStatus::Served) => OrderStatus::PartiallyReady,
            $any(OrderItemStatus::Preparing) => OrderStatus::Preparing,
            $all(OrderItemStatus::Accepted) => OrderStatus::Accepted,
            $all(OrderItemStatus::SentToStation, OrderItemStatus::Accepted) => OrderStatus::SentToStation,
            default => OrderStatus::Placed,
        };

        if ($derived === $current) {
            return;
        }

        $order->status = $derived->value;
        $this->logKdsEvent($order, 'status_derived', $actor, [], $current->value, $derived->value);
        $this->tables->syncForOrder($order);
    }

    /** KDS kaynaklı operasyonel olay (order_events zaman çizelgesine düşer). */
    private function logKdsEvent(Order $order, string $type, ?User $actor, array $payload = [], ?string $from = null, ?string $to = null, ?OrderItem $item = null): void
    {
        $event = new OrderEvent([
            'type' => $type,
            'from_status' => $from,
            'to_status' => $to,
            'payload' => $payload === [] ? null : $payload,
        ]);
        $event->tenant_id = $order->tenant_id;
        $event->branch_id = $order->branch_id;
        $event->order_id = $order->getKey();
        $event->order_item_id = $item?->getKey();
        $event->user_id = $actor?->getKey();
        $event->save();
    }
}
