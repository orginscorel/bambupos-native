<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\PinService;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Enums\ServiceType;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\IdempotencyStore;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Support\OrderPresenter;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Panel sipariş API'si (garson ekranları). Tüm sorgular tenant-scope'lu;
 * mutasyonlar OrderService'te (transaction + kilit + sürüm + idempotency).
 */
class OrderController extends Controller
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly IdempotencyStore $idempotency,
    ) {
    }

    /* ---------------- Listeleme ---------------- */

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        $query = Order::query()->with(['table:id,name,number']);

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        if ($request->filled('status')) {
            $query->where('status', (string) $request->query('status'));
        }

        if ($request->filled('channel')) {
            $query->where('channel', (string) $request->query('channel'));
        }

        if ($request->boolean('open')) {
            $query->whereNotIn('status', OrderStatus::closedValues());
        }

        $orders = $query->latest('id')->paginate(min((int) $request->query('per_page', 50), 200));
        $orders->getCollection()->transform(fn (Order $o): array => OrderPresenter::summary($o));

        return response()->json(['orders' => $orders]);
    }

    /**
     * Masa ızgarası: şubenin masaları + açık adisyon özetleri + masasız
     * kanalların (paket/gel-al/kiosk) açık siparişleri + onay bekleyen QR.
     */
    public function board(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        $branchId = (int) $request->query('branch_id', 0);

        $tables = \App\Modules\Tables\Models\Table::query()
            ->with(['area:id,name,floor_id', 'area.floor:id,name'])
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->where('is_active', true)
            ->orderBy('number')->orderBy('name')
            ->get();

        // Açık adisyonlar + ön-ödemeli (kiosk POS) ama henüz teslim edilmemiş
        // siparişler. Kiosk siparişi başta 'paid' olur; teslim edilene kadar
        // panoda görünmeli (aksi halde kasadan/panodan "kayboluyordu").
        $openOrders = Order::query()
            ->with(['table:id,name,number', 'items'])
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->operationallyVisible()
            ->orderBy('id')
            ->get();

        $byTable = $openOrders->whereNotNull('table_id')->groupBy('table_id');

        $tableCards = $tables->map(function ($table) use ($byTable): array {
            $status = $table->status instanceof \App\Modules\Venue\Enums\TableStatus
                ? $table->status
                : \App\Modules\Venue\Enums\TableStatus::tryFrom((string) $table->status) ?? \App\Modules\Venue\Enums\TableStatus::Available;

            return [
                'id' => $table->id,
                'name' => $table->name,
                'number' => $table->number,
                'capacity' => $table->capacity,
                'area_name' => $table->area?->name,
                'floor_name' => $table->area?->floor?->name,
                'status' => $status->value,
                'status_label' => $status->label(),
                'status_icon' => $status->icon(),
                'status_variant' => $status->variant(),
                'orders' => ($byTable->get($table->id) ?? collect())
                    ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
            ];
        });

        // Açık servis talepleri (garson çağır / hesap iste / su iste)
        $serviceRequests = \App\Modules\Orders\Models\ServiceRequest::query()
            ->with('table:id,name,number')
            ->when($branchId > 0, fn ($q) => $q->where('branch_id', $branchId))
            ->where('status', 'open')
            ->orderBy('id')
            ->get()
            ->map(fn (\App\Modules\Orders\Models\ServiceRequest $sr): array => [
                'id' => $sr->id,
                'kind' => $sr->kind,
                'kind_label' => $sr->kindLabel(),
                'kind_icon' => $sr->kindIcon(),
                'table_id' => $sr->table_id,
                'table_name' => $sr->table?->name,
                'created_at' => $sr->created_at?->toIso8601String(),
            ])->values()->all();

        return response()->json([
            'tables' => $tableCards,
            'channel_orders' => $openOrders->whereNull('table_id')
                ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
            'pending_approval' => $openOrders->where('status', OrderStatus::PendingApproval->value)
                ->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
            'service_requests' => $serviceRequests,
        ]);
    }

    public function show(Request $request, Order $order): JsonResponse
    {
        $this->authorize('view', $order);

        $order->load(['items.options', 'events.user', 'table:id,name,number', 'openedBy:id,name']);

        return response()->json(['order' => OrderPresenter::detail($order)]);
    }

    /* ---------------- Açma ---------------- */

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Order::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'channel' => ['sometimes', Rule::enum(OrderChannel::class)],
            'service_type' => ['sometimes', Rule::enum(ServiceType::class)],
            'table_id' => ['nullable', 'integer'],
            'guest_count' => ['nullable', 'integer', 'min:1', 'max:200'],
            'note' => ['nullable', 'string', 'max:500'],
            'customer_name' => ['nullable', 'string', 'max:120'],
            'customer_phone' => ['nullable', 'string', 'max:32'],
            'total_minor' => ['sometimes', 'integer', 'min:0'], // Faz-1 uyumluluk (kullanılmaz)
        ]);

        $branch = Branch::query()->find((int) $data['branch_id']); // scoped: yabancı şube çözülmez

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $data['branch_id'] = (int) $branch->id;
        $data['channel'] = $data['channel'] ?? OrderChannel::Table->value;

        // Rezervasyon ↔ walk-in çakışması (§8): boş görünen masaya YENİ adisyon
        // açılırken masanın yaklaşan/aktif rezervasyonu varsa personel ONAYI
        // (confirm=true) olmadan açma; uyarı döndür (Board onay diyaloğu).
        if (! $request->boolean('confirm')) {
            $warning = $this->reservationConflictWarning($data);

            if ($warning !== null) {
                return response()->json($warning, 409);
            }
        }

        $order = $this->orders->open($data, $request->user());

        // Tek-adisyon kuralı: masada zaten açık adisyon varsa YENİSİ
        // açılmaz, var olan İDEMPOTENT biçimde döner (201 DEĞİL, 200 —
        // yeni kaynak oluşmadı).
        $status = $order->wasRecentlyCreated ? 201 : 200;

        // Yeni oturma + masaya bağlıysa: rezervasyonu ilerlet (seated) ya da
        // net çakışma işaretle (ReservationService; idempotent open'da çalışmaz).
        if ($order->wasRecentlyCreated && $order->table_id !== null) {
            $this->progressReservationForWalkIn($order, $request->user());
        }

        return response()->json(['order' => OrderPresenter::summary($order->fresh(['table']))], $status);
    }

    /* ---------------- Kalemler ---------------- */

    public function addItem(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'product_id' => ['required', 'integer'],
            'variant_id' => ['nullable', 'integer'],
            'qty' => ['required', 'integer', 'min:1', 'max:100'],
            'option_ids' => ['sometimes', 'array', 'max:30'],
            'option_ids.*' => ['integer'],
            'note' => ['nullable', 'string', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        [$response, $status, $replayed] = $this->idempotency->run(
            (int) $order->tenant_id,
            $request->header('Idempotency-Key'),
            'orders.items.add',
            function () use ($order, $data, $request): array {
                $this->orders->addItem($order, $data, $request->user(), $data['expected_version'] ?? null);

                return [['order' => $this->freshDetail($order)], 201];
            },
        );

        return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
    }

    public function updateItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'qty' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'option_ids' => ['sometimes', 'array', 'max:30'],
            'option_ids.*' => ['integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->updateItem($order, $item, $data, $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function removeItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $this->orders->removeItem($order, $item, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function cancelItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('cancel', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->cancelItem($order, $item, $data['reason'], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function compItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('comp', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->compItem($order, $item, $data['reason'], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function setItemStatus(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'status' => ['required', Rule::enum(OrderItemStatus::class)],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->setItemStatus($order, $item, OrderItemStatus::from($data['status']), $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function moveItem(Request $request, Order $order, OrderItem $item): JsonResponse
    {
        $this->authorize('update', $order);
        $this->assertItemBelongs($order, $item);

        $data = $request->validate([
            'table_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $target = $this->orders->moveItem($order, $item, (int) $data['table_id'], $request->user(), $data['expected_version'] ?? null);

        return response()->json([
            'order' => $this->freshDetail($order),
            'target_order' => OrderPresenter::summary($target->fresh(['table', 'items'])),
        ]);
    }

    /* ---------------- Durum ---------------- */

    public function setStatus(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'status' => ['required', Rule::enum(OrderStatus::class)],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->transition($order, OrderStatus::from($data['status']), $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function approve(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->approve($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function requestBill(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->requestBill($order, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /* ---------------- İndirim / ödeme / iptal / iade (§12.3) ---------------- */

    public function discount(Request $request, Order $order): JsonResponse
    {
        $this->authorize('discount', $order);

        $data = $request->validate([
            'type' => ['required', Rule::in(['percent', 'amount'])],
            'value' => ['required', 'numeric', 'gt:0'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'approver_email' => ['nullable', 'email'],
            'approver_pin' => ['nullable', 'string', 'max:10'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $approver = $this->resolveApprover($request, $data);

        $this->orders->applyDiscount($order, [
            'type' => $data['type'],
            'value' => $data['type'] === 'percent' ? (float) $data['value'] : (int) $data['value'],
            'reason' => $data['reason'],
        ], $request->user(), $approver, $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * ESKİ ödeme ucu (Faz-3 uyumluluk) — Faz-5'ten itibaren kayıt
     * `payments` tablosuna düşer (ADR-010 tek doğruluk kaynağı).
     * 'card' = entegrasyonsuz POS kaydı (kayıt-onaylı, anında).
     * Yeni ekranlar /api/v1/orders/{order}/payments ucunu kullanır.
     */
    public function pay(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'amount_minor' => ['required', 'integer', 'min:1'],
            'method' => ['required', Rule::in(['cash', 'card'])],
            'expected_version' => ['nullable', 'integer'],
        ]);

        app(\App\Modules\Payments\Services\PaymentService::class)->pay($order, [
            'method' => $data['method'] === 'card'
                ? \App\Modules\Payments\Enums\PaymentMethod::CreditCard->value
                : \App\Modules\Payments\Enums\PaymentMethod::Cash->value,
            'amount_minor' => (int) $data['amount_minor'],
            'provider' => $data['method'] === 'card' ? 'card_present' : null,
        ], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function cancel(Request $request, Order $order): JsonResponse
    {
        $this->authorize('cancel', $order);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->cancel($order, $data['reason'], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /**
     * Adisyonun TAM iadesi — Faz-5'ten itibaren `payments` üzerinden
     * yürür (her başarılı ödemeye iade satırı açılır; ADR-010).
     * payments kaydı olmayan eski adisyonlar için eski yol korunur.
     */
    public function refund(Request $request, Order $order): JsonResponse
    {
        $this->authorize('refund', $order);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $hasPayments = \App\Modules\Payments\Models\Payment::withoutTenancy()
            ->where('order_id', $order->getKey())
            ->where('kind', 'payment')
            ->exists();

        if ($hasPayments) {
            app(\App\Modules\Payments\Services\PaymentService::class)
                ->refundOrderFully($order, $data['reason'], $request->user(), $data['expected_version'] ?? null);
        } else {
            $this->orders->refund($order, $data['reason'], $request->user(), $data['expected_version'] ?? null);
        }

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    /* ---------------- Taşı / birleştir / böl ---------------- */

    public function move(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'table_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->moveOrder($order, (int) $data['table_id'], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function merge(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'source_order_id' => ['required', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $source = Order::query()->find((int) $data['source_order_id']); // scoped

        if ($source === null) {
            throw ValidationException::withMessages(['source_order_id' => ['Kaynak adisyon bulunamadı.']]);
        }

        $this->authorize('update', $source);

        $this->orders->merge($order, $source, $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->freshDetail($order)]);
    }

    public function split(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'mode' => ['required', Rule::in(['items', 'equal', 'persons'])],
            'item_ids' => ['required_if:mode,items', 'array'],
            'item_ids.*' => ['integer'],
            'ways' => ['required_if:mode,equal', 'integer'],
            'amounts' => ['required_if:mode,persons', 'array'],
            'amounts.*' => ['integer', 'min:0'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        if ($data['mode'] === 'items') {
            $newOrder = $this->orders->splitByItems($order, array_map('intval', $data['item_ids']), $request->user(), $data['expected_version'] ?? null);

            return response()->json([
                'order' => $this->freshDetail($order),
                'new_order' => OrderPresenter::summary($newOrder->fresh(['table', 'items'])),
            ]);
        }

        $shares = $this->orders->splitShares($order, [
            'mode' => $data['mode'],
            'ways' => isset($data['ways']) ? (int) $data['ways'] : null,
            'amounts' => $data['amounts'] ?? [],
        ], $request->user());

        return response()->json(['order' => $this->freshDetail($order), 'shares_minor' => $shares]);
    }

    /* ---------------- Yardımcılar ---------------- */

    private function freshDetail(Order $order): array
    {
        $fresh = Order::query()
            ->with(['items.options', 'events.user', 'table:id,name,number', 'openedBy:id,name'])
            ->findOrFail($order->getKey());

        return OrderPresenter::detail($fresh);
    }

    private function assertItemBelongs(Order $order, OrderItem $item): void
    {
        if ((int) $item->order_id !== (int) $order->getKey()) {
            abort(404);
        }
    }

    private function expectedVersion(Request $request): ?int
    {
        $v = $request->input('expected_version');

        return $v === null || $v === '' ? null : (int) $v;
    }

    /**
     * Rezervasyon ↔ walk-in çakışma ön-kontrolü (§8). Yalnız masaya
     * BAĞLANACAK (table/qr kanal ya da dine_in) ve masasında HENÜZ açık
     * adisyon OLMAYAN (gerçek yeni oturma) açılışlar denetlenir. Yaklaşan/
     * aktif rezervasyon varsa Board'a onay için uyarı payload'ı döner.
     * En kötü durumda (rezervasyon modülü sorunu) açılışı ENGELLEMEZ.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>|null
     */
    private function reservationConflictWarning(array $data): ?array
    {
        $channel = OrderChannel::tryFrom((string) $data['channel']) ?? OrderChannel::Table;
        $serviceType = isset($data['service_type'])
            ? (ServiceType::tryFrom((string) $data['service_type']) ?? ServiceType::fromChannel($channel))
            : ServiceType::fromChannel($channel);
        $tableId = (int) ($data['table_id'] ?? 0);

        if ($tableId <= 0 || ! ($channel->usesTable() || $serviceType->requiresTable())) {
            return null;
        }

        if (! \App\Modules\Reservations\Support\ReservationFeature::enabled((int) $data['branch_id'])) {
            return null;
        }

        try {
            $table = \App\Modules\Tables\Models\Table::query()
                ->where('branch_id', (int) $data['branch_id'])
                ->find($tableId);

            if ($table === null) {
                return null; // open() zaten alan-bazlı doğrulama hatası verir
            }

            // Zaten açık adisyon varsa açılış İDEMPOTENT (yeni oturma değil) → uyarma.
            $hasOpen = Order::query()
                ->where('table_id', $tableId)
                ->whereNotIn('status', OrderStatus::closedValues())
                ->exists();

            if ($hasOpen) {
                return null;
            }

            $reservation = app(\App\Modules\Reservations\Services\ReservationTableSync::class)
                ->imminentReservationForTable($table);

            if ($reservation === null) {
                return null;
            }

            $time = $reservation->localReservedAt()->format('H:i');

            return [
                'requires_confirmation' => true,
                'reason' => 'reservation_conflict',
                'message' => sprintf('Bu masa %s %s için rezerve — yine de açılsın mı?', $time, $reservation->customer_name),
                'reservation' => [
                    'id' => $reservation->id,
                    'customer_name' => $reservation->customer_name,
                    'reserved_time' => $time,
                    'party_size' => (int) $reservation->party_size,
                    'status' => $reservation->status->value,
                    'status_label' => $reservation->status->label(),
                ],
            ];
        } catch (\Throwable $e) {
            report($e); // rezervasyon denetimi adisyon açılışını bozmasın (fail-open)

            return null;
        }
    }

    /**
     * Walk-in rezervasyonlu masaya oturunca ilgili rezervasyonu ilerletir
     * (seated) ya da net çakışma olarak işaretler (ReservationService).
     * Best-effort: rezervasyon tarafı hata verse de adisyon akışı sürer.
     */
    private function progressReservationForWalkIn(Order $order, ?User $actor): void
    {
        if (! \App\Modules\Reservations\Support\ReservationFeature::enabled((int) $order->branch_id)) {
            return;
        }

        try {
            $table = \App\Modules\Tables\Models\Table::query()->find($order->table_id);

            if ($table === null) {
                return;
            }

            $reservation = app(\App\Modules\Reservations\Services\ReservationTableSync::class)
                ->imminentReservationForTable($table);

            if ($reservation !== null) {
                app(\App\Modules\Reservations\Services\ReservationService::class)
                    ->markWalkInSeated($reservation, $actor);
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Eşik üstü indirim onayı: yönetici e-posta + PIN (Identity/PinService).
     * Onaylayan AYNI kiracıda olmalı ve personel yönetim yetkisi taşımalı.
     *
     * @param  array<string, mixed>  $data
     */
    private function resolveApprover(Request $request, array $data): ?User
    {
        if (empty($data['approver_email']) || empty($data['approver_pin'])) {
            return null;
        }

        /** @var User|null $approver */
        $approver = User::query()
            ->where('tenant_id', $request->user()->tenant_id)
            ->where('email', $data['approver_email'])
            ->first();

        if ($approver === null) {
            throw ValidationException::withMessages(['approver_email' => ['Onaylayan bulunamadı.']]);
        }

        if (! $approver->hasPermission('staff.manage') || ! $approver->hasPermission('orders.discount')) {
            throw ValidationException::withMessages(['approver_email' => ['Onaylayanın yönetici (personel yönetimi + indirim) yetkisi yok.']]);
        }

        if (! app(PinService::class)->verify($approver, (string) $data['approver_pin'])) {
            throw ValidationException::withMessages(['approver_pin' => ['PIN doğrulanamadı.']]);
        }

        return $approver;
    }
}
