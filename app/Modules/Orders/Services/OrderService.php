<?php

namespace App\Modules\Orders\Services;

use App\Modules\Catalog\Models\Option;
use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductVariant;
use App\Modules\Catalog\Support\Money;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderEvent;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Tables\Models\Table;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpException;

/**
 * Adisyon çekirdeği (görev §2–§6). TÜM mutasyonlar buradan geçer:
 *
 *  - Transaction + satır kilidi (lockForUpdate) + sipariş sürüm numarası
 *    (optimistic locking) — iki garson aynı adisyona aynı anda dokunursa
 *    ikinci yazan ya kilidi bekler ya 409 alır; kayıp güncelleme olmaz.
 *  - Fiyat/KDV/seçenek SATIŞ ANINDA snapshot'lanır (prompt §25) —
 *    ürün fiyatı sonra değişse de adisyon değişmez.
 *  - Tutar hesabı TEK yerdedir (computeLine + recomputeTotals; ADR-007).
 *  - Sipariş olayları TableStatusSynchronizer ile masa durumunu sürer.
 *  - İkram/indirim/iptal: neden zorunlu; işlemi yapan + yetkilendiren,
 *    önceki tutar ve zaman order_events + audit_logs'a yazılır (§12.3).
 */
class OrderService
{
    public function __construct(
        private readonly TableStatusSynchronizer $tables,
        private readonly AuditLogger $audit,
    ) {
    }

    /* =========================================================
     |  Kilit + sürüm çekirdeği (prompt §12.4)
     * ========================================================= */

    /**
     * Adisyonu transaction içinde SATIR KİLİDİYLE yeniden yükler, sürümü
     * doğrular, işi çalıştırır ve sürümü artırır.
     *
     * @template T
     * @param  callable(Order): T  $work
     * @return T
     */
    public function withLockedOrder(Order $order, ?int $expectedVersion, callable $work): mixed
    {
        return DB::transaction(function () use ($order, $expectedVersion, $work) {
            /** @var Order $locked */
            $locked = Order::query()->lockForUpdate()->findOrFail($order->getKey());

            if ($expectedVersion !== null && (int) $locked->version !== $expectedVersion) {
                throw new HttpException(409, sprintf(
                    'Adisyon bu sırada başka bir kullanıcı tarafından değiştirildi (sürüm %d → %d). Ekranı yenileyin.',
                    $expectedVersion,
                    (int) $locked->version,
                ));
            }

            $result = $work($locked);

            $locked->version = (int) $locked->version + 1;
            $locked->save();

            return $result;
        });
    }

    /* =========================================================
     |  Adisyon açma
     * ========================================================= */

    /**
     * @param array{
     *   branch_id: int, channel: string, table_id?: int|null,
     *   guest_count?: int|null, note?: string|null,
     *   customer_name?: string|null, customer_phone?: string|null,
     *   status?: OrderStatus
     * } $data
     */
    public function open(array $data, ?User $actor): Order
    {
        $channel = OrderChannel::tryFrom($data['channel']) ?? OrderChannel::Table;
        $status = $data['status'] ?? OrderStatus::Placed;

        $table = null;

        if ($channel->usesTable()) {
            $table = Table::withoutTenancy()->find($data['table_id'] ?? 0);

            if ($table === null || (int) $table->branch_id !== (int) $data['branch_id']) {
                throw ValidationException::withMessages(['table_id' => ['Masa bu şubede bulunamadı.']]);
            }

            if (! $table->is_active) {
                throw ValidationException::withMessages(['table_id' => ['Masa kullanım dışı.']]);
            }
        }

        return DB::transaction(function () use ($data, $channel, $status, $table, $actor): Order {
            $order = new Order([
                'status' => $status->value,
                'channel' => $channel->value,
                'guest_count' => $data['guest_count'] ?? null,
                'note' => $data['note'] ?? null,
                'customer_name' => $data['customer_name'] ?? null,
                'customer_phone' => $data['customer_phone'] ?? null,
            ]);
            $order->branch_id = (int) $data['branch_id'];
            $order->table_id = $table?->getKey();
            $order->opened_by_id = $actor?->getKey();
            $order->placed_at = $status === OrderStatus::Placed ? now() : null;

            if ($channel === OrderChannel::Qr) {
                $order->public_token = Order::generatePublicToken();
            }

            $order->save();

            $this->logEvent($order, 'opened', $actor, ['channel' => $channel->value], null, $status->value);
            $this->tables->syncForOrder($order);

            return $order;
        });
    }

    /* =========================================================
     |  Kalem işlemleri (snapshot — prompt §25)
     * ========================================================= */

    /**
     * @param array{
     *   product_id: int, variant_id?: int|null, qty: int,
     *   option_ids?: array<int, int>, note?: string|null
     * } $data
     */
    public function addItem(Order $order, array $data, ?User $actor, ?int $expectedVersion = null): OrderItem
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($data, $actor): OrderItem {
            $this->assertItemsChangeable($locked);

            if ($locked->items()->count() >= (int) config('orders.max_items_per_order', 200)) {
                throw ValidationException::withMessages(['items' => ['Adisyon kalem sınırına ulaştı.']]);
            }

            $item = $this->buildItem($locked, $data, $actor);

            $this->logEvent($locked, 'item_added', $actor, [
                'name' => $item->name,
                'qty' => $item->qty,
                'unit_price_minor' => $item->unit_price_minor,
                'options_price_minor' => $item->options_price_minor,
                'line_total_minor' => $item->line_total_minor,
            ], item: $item);

            $this->recomputeTotals($locked);
            $this->deriveKitchenStatus($locked, $actor);

            return $item;
        });
    }

    /** Snapshot'lı kalem üretimi (public sipariş de bunu kullanır). */
    private function buildItem(Order $order, array $data, ?User $actor): OrderItem
    {
        $channel = $order->channelEnum();

        /** @var Product|null $product */
        $product = Product::withoutTenancy()
            ->with(['optionGroups.options', 'variants'])
            ->where('tenant_id', $order->tenant_id)
            ->find((int) $data['product_id']);

        if ($product === null || ! $product->is_active) {
            throw ValidationException::withMessages(['product_id' => ['Ürün bulunamadı veya satışta değil.']]);
        }

        if (! $product->is_available) {
            throw ValidationException::withMessages(['product_id' => [$product->name.' şu an mevcut değil (tükendi).']]);
        }

        $channels = $product->channels;
        if (is_array($channels) && $channels !== [] && ! in_array($channel->catalogChannelKey(), $channels, true)) {
            throw ValidationException::withMessages(['product_id' => [$product->name.' bu kanalda satışa kapalı.']]);
        }

        $qty = (int) $data['qty'];
        $min = max(1, (int) $product->min_order_qty);
        $max = $product->max_order_qty !== null ? (int) $product->max_order_qty : 100;

        if ($qty < $min || $qty > $max) {
            throw ValidationException::withMessages(['qty' => ["Adet {$min}–{$max} aralığında olmalı."]]);
        }

        // Varyant: ürünün kendi varyantı olmalı; fiyatı birim fiyat OLUR.
        $variant = null;
        if (! empty($data['variant_id'])) {
            $variant = $product->variants->firstWhere('id', (int) $data['variant_id']);

            if (! $variant instanceof ProductVariant || ! $variant->is_active) {
                throw ValidationException::withMessages(['variant_id' => ['Varyant bu ürüne ait değil.']]);
            }
        }

        $unitMinor = $variant !== null
            ? (int) $variant->price_minor
            : $this->channelUnitPrice($product, $channel);

        // Seçenekler: ürünün bağlı gruplarındaki seçenekler olmalı; grup
        // kuralları (zorunlu/min/max) doğrulanır; fiyatlar snapshot'lanır.
        $optionRows = $this->resolveOptions($product, array_map('intval', $data['option_ids'] ?? []));

        $optionsMinor = 0;
        foreach ($optionRows as [$group, $option, $effectiveMinor]) {
            $optionsMinor += $effectiveMinor;
        }

        $taxRate = (float) $product->tax_rate;

        $item = new OrderItem([
            'product_id' => $product->getKey(),
            'variant_id' => $variant?->getKey(),
            'status' => OrderItemStatus::Placed->value,
            'qty' => $qty,
            'name' => $product->name,
            'variant_name' => $variant?->name,
            'unit_price_minor' => $unitMinor,
            'options_price_minor' => $optionsMinor,
            'tax_rate' => $taxRate,
            'station' => $product->station,
            'note' => $data['note'] ?? null,
        ]);
        $item->tenant_id = $order->tenant_id;
        $item->order_id = $order->getKey();
        $item->added_by_id = $actor?->getKey();
        $this->computeLine($item);
        $item->save();

        foreach ($optionRows as [$group, $option, $effectiveMinor]) {
            $item->options()->create([
                'tenant_id' => $order->tenant_id,
                'option_id' => $option->getKey(),
                'group_name' => $group->name,
                'option_name' => $option->name,
                'price_minor' => $effectiveMinor, // efektif fiyat (free_limit içi = 0)
            ]);
        }

        return $item;
    }

    /**
     * @param array{qty?: int, note?: string|null, option_ids?: array<int, int>} $data
     */
    public function updateItem(Order $order, OrderItem $item, array $data, ?User $actor, ?int $expectedVersion = null): OrderItem
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $data, $actor): OrderItem {
            $this->assertItemsChangeable($locked);
            $item = $this->freshItem($locked, $item);

            if (! in_array($item->statusEnum(), [OrderItemStatus::Placed, OrderItemStatus::SentToStation, OrderItemStatus::Accepted], true)) {
                throw ValidationException::withMessages(['item' => ['Hazırlanmaya başlanan kalem değiştirilemez; iptal/ikram yolunu kullanın.']]);
            }

            $old = ['qty' => $item->qty, 'note' => $item->note, 'options_price_minor' => $item->options_price_minor];

            if (array_key_exists('qty', $data)) {
                $qty = (int) $data['qty'];

                if ($qty < 1 || $qty > 100) {
                    throw ValidationException::withMessages(['qty' => ['Adet 1–100 aralığında olmalı.']]);
                }

                $item->qty = $qty;
            }

            if (array_key_exists('note', $data)) {
                $item->note = $data['note'];
            }

            if (array_key_exists('option_ids', $data)) {
                // Seçenek değişikliği = o ANIN fiyatlarıyla yeni snapshot.
                $product = $item->product_id !== null
                    ? Product::withoutTenancy()->with('optionGroups.options')
                        ->where('tenant_id', $locked->tenant_id)->find($item->product_id)
                    : null;

                if ($product === null) {
                    throw ValidationException::withMessages(['option_ids' => ['Ürün kataloğu kaydı bulunamadığından seçenek değiştirilemez.']]);
                }

                $optionRows = $this->resolveOptions($product, array_map('intval', $data['option_ids']));

                $item->options()->delete();
                $optionsMinor = 0;

                foreach ($optionRows as [$group, $option, $effectiveMinor]) {
                    $optionsMinor += $effectiveMinor;
                    $item->options()->create([
                        'tenant_id' => $locked->tenant_id,
                        'option_id' => $option->getKey(),
                        'group_name' => $group->name,
                        'option_name' => $option->name,
                        'price_minor' => $effectiveMinor, // efektif fiyat (free_limit içi = 0)
                    ]);
                }

                $item->options_price_minor = $optionsMinor;
            }

            $this->computeLine($item);
            $item->save();

            $this->logEvent($locked, 'item_updated', $actor, [
                'old' => $old,
                'new' => ['qty' => $item->qty, 'note' => $item->note, 'options_price_minor' => $item->options_price_minor],
            ], item: $item);

            $this->recomputeTotals($locked);

            return $item;
        });
    }

    /** Henüz mutfağa gitmemiş kalemi adisyondan ÇIKARIR (iz: order_events). */
    public function removeItem(Order $order, OrderItem $item, ?User $actor, ?int $expectedVersion = null): void
    {
        $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $actor): void {
            $this->assertItemsChangeable($locked);
            $item = $this->freshItem($locked, $item);

            if ($item->statusEnum() !== OrderItemStatus::Placed) {
                throw ValidationException::withMessages(['item' => ['İstasyona giden kalem silinemez; iptal (nedenli) kullanın.']]);
            }

            $this->logEvent($locked, 'item_removed', $actor, [
                'name' => $item->name,
                'qty' => $item->qty,
                'line_total_minor' => $item->line_total_minor,
            ]);

            $item->options()->delete();
            $item->delete();

            $this->recomputeTotals($locked);
            $this->deriveKitchenStatus($locked, $actor);
            $this->closeIfEmptied($locked, $actor);
        });
    }

    /** Kalem iptali — NEDEN ZORUNLU; denetim kaydına düşer (§12.3). */
    public function cancelItem(Order $order, OrderItem $item, string $reason, User $actor, ?int $expectedVersion = null): OrderItem
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $reason, $actor): OrderItem {
            $this->assertItemsChangeable($locked);
            $item = $this->freshItem($locked, $item);

            if (! $item->statusEnum()->canTransitionTo(OrderItemStatus::Cancelled)) {
                throw ValidationException::withMessages(['item' => ['Bu kalem iptal edilemez (servis edildi ya da zaten iptal).']]);
            }

            $previousTotal = (int) $item->line_total_minor;

            $item->status = OrderItemStatus::Cancelled->value;
            $item->cancel_reason = $reason;
            $item->cancelled_by_id = $actor->getKey();
            $item->cancelled_at = now();
            $this->computeLine($item);
            $item->save();

            $this->logEvent($locked, 'item_cancelled', $actor, [
                'name' => $item->name,
                'reason' => $reason,
                'previous_total_minor' => $previousTotal,
            ], item: $item);

            $this->audit->log('orders.item_cancelled', $locked, null, [
                'item' => $item->name,
                'qty' => $item->qty,
                'reason' => $reason,
                'previous_total_minor' => $previousTotal,
                'performed_by' => $actor->getKey(),
            ]);

            $this->recomputeTotals($locked);
            $this->deriveKitchenStatus($locked, $actor);
            $this->closeIfEmptied($locked, $actor);

            return $item;
        });
    }

    /** İkram — NEDEN ZORUNLU; önceki tutar + yapan denetime yazılır (§12.3). */
    public function compItem(Order $order, OrderItem $item, string $reason, User $actor, ?int $expectedVersion = null): OrderItem
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $reason, $actor): OrderItem {
            $this->assertItemsChangeable($locked);
            $item = $this->freshItem($locked, $item);

            if (! $item->isActive()) {
                throw ValidationException::withMessages(['item' => ['İptal edilmiş kalem ikram edilemez.']]);
            }

            if ($item->is_comp) {
                throw ValidationException::withMessages(['item' => ['Kalem zaten ikram.']]);
            }

            $previousTotal = (int) $item->line_total_minor;

            $item->is_comp = true;
            $item->comp_reason = $reason;
            $item->comp_by_id = $actor->getKey();
            $this->computeLine($item);
            $item->save();

            $this->logEvent($locked, 'item_comped', $actor, [
                'name' => $item->name,
                'reason' => $reason,
                'previous_total_minor' => $previousTotal,
                'comp_value_minor' => $this->lineGross($item),
            ], item: $item);

            $this->audit->log('orders.item_comped', $locked, null, [
                'item' => $item->name,
                'reason' => $reason,
                'previous_total_minor' => $previousTotal,
                'comp_value_minor' => $this->lineGross($item),
                'performed_by' => $actor->getKey(),
            ]);

            $this->recomputeTotals($locked);

            return $item;
        });
    }

    /** Kalem durumunu ilerlet (mutfak/servis akışı) + sipariş durumunu türet. */
    public function setItemStatus(Order $order, OrderItem $item, OrderItemStatus $to, ?User $actor, ?int $expectedVersion = null): OrderItem
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $to, $actor): OrderItem {
            $item = $this->freshItem($locked, $item);
            $from = $item->statusEnum();

            if ($to === OrderItemStatus::Cancelled) {
                throw ValidationException::withMessages(['status' => ['İptal için nedenli iptal ucunu kullanın.']]);
            }

            if (! $from->canTransitionTo($to)) {
                throw ValidationException::withMessages(['status' => [
                    sprintf('Kalem "%s" durumundan "%s" durumuna geçemez.', $from->label(), $to->label()),
                ]]);
            }

            $item->status = $to->value;
            $item->save();

            $this->logEvent($locked, 'item_status_changed', $actor, ['name' => $item->name], $from->value, $to->value, $item);
            $this->deriveKitchenStatus($locked, $actor);

            return $item;
        });
    }

    /* =========================================================
     |  Sipariş durum makinesi (görev §2)
     * ========================================================= */

    /**
     * Garson/mutfak durum geçişi. Ödeme/iptal/iade hedefleri kendi
     * uçlarını kullanır (guard'ları farklı).
     */
    public function transition(Order $order, OrderStatus $to, ?User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($to, $actor): Order {
            if (in_array($to, [OrderStatus::Paid, OrderStatus::PartiallyPaid, OrderStatus::Cancelled, OrderStatus::Refunded], true)) {
                throw ValidationException::withMessages(['status' => ['Bu duruma yalnız ödeme/iptal/iade işlemleriyle geçilir.']]);
            }

            $this->applyTransition($locked, $to, $actor);

            // Sipariş bütünü ilerletildiyse geride kalan kalemler de taşınır
            // (ör. sipariş "Servis edildi" → tüm aktif kalemler served).
            $this->cascadeItemsForward($locked, $to, $actor);

            return $locked;
        });
    }

    public function requestBill(Order $order, ?User $actor, ?int $expectedVersion = null): Order
    {
        return $this->transition($order, OrderStatus::BillRequested, $actor, $expectedVersion);
    }

    /** QR siparişi onayı: Onay bekliyor → Sipariş alındı. */
    public function approve(Order $order, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($actor): Order {
            $this->applyTransition($locked, OrderStatus::Placed, $actor);
            $locked->placed_at ??= now();

            return $locked;
        });
    }

    /** Makine denetimli ortak geçiş. */
    private function applyTransition(Order $order, OrderStatus $to, ?User $actor): void
    {
        $from = $order->statusEnum();

        if (! $from->canTransitionTo($to)) {
            throw ValidationException::withMessages(['status' => [
                sprintf('"%s" durumundan "%s" durumuna geçilemez.', $from->label(), $to->label()),
            ]]);
        }

        $order->status = $to->value;

        if ($to === OrderStatus::Placed) {
            $order->placed_at ??= now();
        }

        $this->logEvent($order, 'status_changed', $actor, [], $from->value, $to->value);
        $this->tables->syncForOrder($order);
    }

    /**
     * KALEMLERDEN TÜRETİLEN sipariş durumu (görev §2): içecek hazırken ana
     * yemek hazırlanıyorsa sipariş "Kısmen hazır"dır. Yalnız mutfak-aşaması
     * durumları arasında çalışır (hesap/ödeme aşamalarını ezmez); yeni kalem
     * eklendiğinde "Servis edildi"den geriye "Kısmen hazır"a dönüş de buradan
     * olur (sistem-türetimi olduğu için makine tablosuna takılmaz, loglanır).
     */
    private function deriveKitchenStatus(Order $order, ?User $actor): void
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

        $derived = $this->deriveFromItemStatuses($statuses->all());

        if ($derived === null || $derived === $current) {
            return;
        }

        $order->status = $derived->value;
        $this->logEvent($order, 'status_derived', $actor, [], $current->value, $derived->value);
        $this->tables->syncForOrder($order);
    }

    /**
     * @param  array<int, OrderItemStatus>  $statuses
     */
    private function deriveFromItemStatuses(array $statuses): ?OrderStatus
    {
        $all = fn (OrderItemStatus ...$set): bool => count(array_filter($statuses, fn ($s) => ! in_array($s, $set, true))) === 0;
        $any = fn (OrderItemStatus ...$set): bool => count(array_filter($statuses, fn ($s) => in_array($s, $set, true))) > 0;

        return match (true) {
            $all(OrderItemStatus::Served) => OrderStatus::Served,
            $all(OrderItemStatus::Ready, OrderItemStatus::Served) => OrderStatus::Ready,
            $any(OrderItemStatus::Ready, OrderItemStatus::Served) => OrderStatus::PartiallyReady,
            $any(OrderItemStatus::Preparing) => OrderStatus::Preparing,
            $all(OrderItemStatus::Accepted) => OrderStatus::Accepted,
            $all(OrderItemStatus::SentToStation, OrderItemStatus::Accepted) => OrderStatus::SentToStation,
            default => OrderStatus::Placed,
        };
    }

    /** Sipariş bütünü ileri alınınca geride kalan aktif kalemleri hizala. */
    private function cascadeItemsForward(Order $order, OrderStatus $to, ?User $actor): void
    {
        $target = match ($to) {
            OrderStatus::SentToStation => OrderItemStatus::SentToStation,
            OrderStatus::Accepted => OrderItemStatus::Accepted,
            OrderStatus::Preparing => OrderItemStatus::Preparing,
            OrderStatus::Ready => OrderItemStatus::Ready,
            OrderStatus::Served => OrderItemStatus::Served,
            default => null,
        };

        if ($target === null) {
            return;
        }

        foreach ($order->items as $item) {
            if ($item->isActive() && $item->statusEnum()->canTransitionTo($target)) {
                $item->status = $target->value;
                $item->save();
            }
        }
    }

    /* =========================================================
     |  İndirim / ödeme / iptal / iade (§12.3)
     * ========================================================= */

    /**
     * Adisyon indirimi. Eşik ÜZERİ indirim yönetici onayı ister (PIN
     * doğrulaması controller'da yapılır, onaylayan buraya gelir).
     *
     * @param array{type: 'percent'|'amount', value: int|float, reason: string} $data
     */
    public function applyDiscount(Order $order, array $data, User $actor, ?User $approver, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($data, $actor, $approver): Order {
            $this->assertItemsChangeable($locked);

            $itemsTotal = (int) $locked->items_total_minor;

            if ($itemsTotal <= 0) {
                throw ValidationException::withMessages(['discount' => ['Boş adisyona indirim uygulanamaz.']]);
            }

            $previous = [
                'discount_minor' => (int) $locked->discount_minor,
                'total_minor' => (int) $locked->total_minor,
            ];

            if ($data['type'] === 'percent') {
                $percent = (float) $data['value'];

                if ($percent <= 0 || $percent > 100) {
                    throw ValidationException::withMessages(['value' => ['Yüzde 0–100 aralığında olmalı.']]);
                }

                $locked->discount_percent = $percent;
                $locked->discount_minor = Money::percent($itemsTotal, $percent);
            } else {
                $amount = (int) $data['value'];

                if ($amount <= 0 || $amount > $itemsTotal) {
                    throw ValidationException::withMessages(['value' => ['İndirim tutarı adisyon toplamını aşamaz.']]);
                }

                $locked->discount_percent = null;
                $locked->discount_minor = $amount;
            }

            $threshold = (float) config('orders.discount_approval_threshold_percent', 10);
            $effectivePercent = $itemsTotal > 0 ? ((int) $locked->discount_minor) * 100 / $itemsTotal : 0;

            if ($effectivePercent > $threshold && $approver === null) {
                // withLockedOrder transaction'ı geri sarar; indirim yazılmaz.
                throw ValidationException::withMessages(['approver' => [
                    sprintf('%%%s üzeri indirim yönetici onayı (PIN) gerektirir.', rtrim(rtrim(number_format($threshold, 2, '.', ''), '0'), '.')),
                ]]);
            }

            $locked->discount_reason = $data['reason'];
            $locked->discount_by_id = $actor->getKey();
            $locked->discount_approved_by_id = $approver?->getKey();

            $this->recomputeTotals($locked);

            $payload = [
                'type' => $data['type'],
                'value' => $data['value'],
                'reason' => $data['reason'],
                'previous' => $previous,
                'discount_minor' => (int) $locked->discount_minor,
                'total_minor' => (int) $locked->total_minor,
                'performed_by' => $actor->getKey(),
                'approved_by' => $approver?->getKey(),
            ];

            $this->logEvent($locked, 'discount_applied', $actor, $payload);
            $this->audit->log('orders.discount_applied', $locked, $previous, $payload);

            return $locked;
        });
    }

    /* =========================================================
     |  Payments modülü köprüsü (Faz-5, ADR-010) — payments tablosu
     |  TEK doğruluk kaynağıdır; paid/refunded buradan TÜRETİLİR.
     |  Bu metotlar YALNIZ withLockedOrder içinden (PaymentService)
     |  çağrılır; kilit ve sürüm dışarıda alınmıştır.
     * ========================================================= */

    /**
     * Tahsilat uygular (delta>0) ya da void geri alır (delta<0).
     * Aşırı tahsil BURADA reddedilir (para değişmezi).
     *
     * @param  array<string, mixed>  $meta  order_events payload eki (payment_id vb.)
     */
    public function applyPaidDelta(Order $locked, int $deltaMinor, string $method, ?User $actor, array $meta = []): void
    {
        $from = $locked->statusEnum();

        if ($deltaMinor === 0) {
            return;
        }

        if ($deltaMinor > 0) {
            if (! $from->isOpen() || in_array($from, [OrderStatus::Draft, OrderStatus::PendingApproval], true)) {
                throw ValidationException::withMessages(['payment' => ['Bu adisyon için ödeme alınamaz (durum: '.$from->label().').']]);
            }

            $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);

            if ($deltaMinor > $remaining) {
                throw ValidationException::withMessages(['amount_minor' => [
                    'Tutar 0 ile kalan tutar ('.Money::toDecimalString($remaining).' TL) arasında olmalı.',
                ]]);
            }

            $locked->paid_minor = (int) $locked->paid_minor + $deltaMinor;
        } else {
            // Void geri alımı: tahsilat hiç olmamış sayılır.
            $locked->paid_minor = max(0, (int) $locked->paid_minor + $deltaMinor);
        }

        $paid = (int) $locked->paid_minor;
        $total = (int) $locked->total_minor;

        if ($total > 0 && $paid >= $total) {
            $to = OrderStatus::Paid;
            $locked->closed_at ??= now();
        } elseif ($paid > 0) {
            $to = OrderStatus::PartiallyPaid;
            $locked->closed_at = null;
        } else {
            // Void ile sıfırlandı → ödeme aşamasına (hesap istendi) döner.
            $to = OrderStatus::BillRequested;
            $locked->closed_at = null;
        }

        $locked->status = $to->value;

        $this->logEvent($locked, $deltaMinor > 0 ? 'payment_recorded' : 'payment_reversed', $actor, $meta + [
            'amount_minor' => abs($deltaMinor),
            'method' => $method,
            'paid_minor' => $paid,
            'total_minor' => $total,
        ], $from->value, $to->value);

        $this->tables->syncForOrder($locked, $to === OrderStatus::Paid ? OrderStatus::Paid : null);
    }

    /**
     * İade uygular: refunded_minor artar (paid_minor DEĞİŞMEZ — brüt
     * tahsilat tarihçesi korunur). Tamamı iade edilen ödenmiş adisyon
     * Refunded durumuna geçer.
     *
     * @param  array<string, mixed>  $meta
     */
    public function applyRefundDelta(Order $locked, int $deltaMinor, ?User $actor, array $meta = []): void
    {
        if ($deltaMinor <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['İade tutarı pozitif olmalı.']]);
        }

        $newRefunded = (int) $locked->refunded_minor + $deltaMinor;

        if ($newRefunded > (int) $locked->paid_minor) {
            throw ValidationException::withMessages(['amount_minor' => ['İade toplamı tahsil edilen tutarı aşamaz.']]);
        }

        $from = $locked->statusEnum();
        $locked->refunded_minor = $newRefunded;

        $to = $from;

        if ($from === OrderStatus::Paid && $newRefunded >= (int) $locked->paid_minor && (int) $locked->paid_minor > 0) {
            $to = OrderStatus::Refunded;
            $locked->status = $to->value;
        }

        $this->logEvent($locked, 'refund_applied', $actor, $meta + [
            'amount_minor' => $deltaMinor,
            'refunded_minor' => $newRefunded,
            'paid_minor' => (int) $locked->paid_minor,
        ], $from->value, $to->value);

        if ($to === OrderStatus::Refunded) {
            $this->tables->syncForOrder($locked, OrderStatus::Refunded);
        }
    }

    /**
     * Nakit yuvarlama düzeltmesi (±99 kuruş sınırı config'te). Toplam
     * yeniden hesaplanır; iz order_events'e düşer.
     */
    public function applyRounding(Order $locked, int $roundingMinor, ?User $actor, string $context = 'cash_rounding'): void
    {
        $max = (int) config('payments.max_rounding_minor', 99);

        if (abs($roundingMinor) > $max) {
            throw ValidationException::withMessages(['rounding' => ["Yuvarlama en fazla ±{$max} kuruş olabilir."]]);
        }

        $previous = (int) $locked->rounding_minor;
        $locked->rounding_minor = $roundingMinor;
        $this->recomputeTotals($locked);

        $this->logEvent($locked, 'rounding_applied', $actor, [
            'context' => $context,
            'previous_rounding_minor' => $previous,
            'rounding_minor' => $roundingMinor,
            'total_minor' => (int) $locked->total_minor,
        ]);
    }

    /**
     * Servis bedeli (prompt §15): yüzde ya da sabit tutar; kalemler
     * değiştikçe yüzdeli bedel yeniden hesaplanır. KDV'siz eklenir
     * (adisyon KDV dökümü kalem bazlıdır).
     *
     * @param  array{type: 'percent'|'amount', value: int|float, reason?: string|null}|null  $data  null → bedeli kaldır
     */
    public function applyServiceCharge(Order $order, ?array $data, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($data, $actor): Order {
            $this->assertItemsChangeable($locked);

            if ((int) $locked->paid_minor > 0) {
                throw ValidationException::withMessages(['service_charge' => ['Tahsilat başlayan adisyonda servis bedeli değiştirilemez.']]);
            }

            $previous = [
                'service_charge_minor' => (int) $locked->service_charge_minor,
                'total_minor' => (int) $locked->total_minor,
            ];

            if ($data === null) {
                $locked->service_charge_percent = null;
                $locked->service_charge_minor = 0;
                $locked->service_charge_reason = null;
            } elseif ($data['type'] === 'percent') {
                $percent = (float) $data['value'];
                $maxPercent = (float) config('payments.max_service_charge_percent', 20);

                if ($percent <= 0 || $percent > $maxPercent) {
                    throw ValidationException::withMessages(['value' => ["Servis bedeli yüzdesi 0–{$maxPercent} aralığında olmalı."]]);
                }

                $locked->service_charge_percent = $percent;
                $locked->service_charge_reason = $data['reason'] ?? null;
            } else {
                $amount = (int) $data['value'];

                if ($amount <= 0 || $amount > (int) $locked->items_total_minor) {
                    throw ValidationException::withMessages(['value' => ['Servis bedeli kalem toplamını aşamaz.']]);
                }

                $locked->service_charge_percent = null;
                $locked->service_charge_minor = $amount;
                $locked->service_charge_reason = $data['reason'] ?? null;
            }

            $this->recomputeTotals($locked);

            $payload = [
                'type' => $data['type'] ?? 'removed',
                'value' => $data['value'] ?? 0,
                'reason' => $data['reason'] ?? null,
                'previous' => $previous,
                'service_charge_minor' => (int) $locked->service_charge_minor,
                'total_minor' => (int) $locked->total_minor,
            ];

            $this->logEvent($locked, 'service_charge_applied', $actor, $payload);
            $this->audit->log('orders.service_charge_applied', $locked, $previous, $payload);

            return $locked;
        });
    }

    /** Sipariş iptali — NEDEN ZORUNLU (§12.3). Ödemesi olan adisyon iade yolunu kullanır. */
    public function cancel(Order $order, string $reason, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($reason, $actor): Order {
            $from = $locked->statusEnum();

            if (! $from->canTransitionTo(OrderStatus::Cancelled)) {
                throw ValidationException::withMessages(['status' => ['Bu adisyon iptal edilemez (durum: '.$from->label().').']]);
            }

            if ((int) $locked->paid_minor > 0) {
                throw ValidationException::withMessages(['status' => ['Ödemesi alınan adisyon iptal edilemez; iade kullanın.']]);
            }

            $locked->status = OrderStatus::Cancelled->value;
            $locked->cancel_reason = $reason;
            $locked->cancelled_by_id = $actor->getKey();
            $locked->cancelled_at = now();
            $locked->closed_at = now();

            $payload = [
                'reason' => $reason,
                'previous_total_minor' => (int) $locked->total_minor,
                'performed_by' => $actor->getKey(),
            ];

            $this->logEvent($locked, 'cancelled', $actor, $payload, $from->value, OrderStatus::Cancelled->value);
            $this->audit->log('orders.cancelled', $locked, ['status' => $from->value], $payload);

            $this->tables->syncForOrder($locked, OrderStatus::Cancelled);

            return $locked;
        });
    }

    /** İade — NEDEN ZORUNLU; yalnız ödenmiş adisyon. */
    public function refund(Order $order, string $reason, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($reason, $actor): Order {
            $from = $locked->statusEnum();

            if (! $from->canTransitionTo(OrderStatus::Refunded)) {
                throw ValidationException::withMessages(['status' => ['Yalnız ödenmiş adisyon iade edilebilir.']]);
            }

            $payload = [
                'reason' => $reason,
                'refunded_minor' => (int) $locked->paid_minor,
                'performed_by' => $actor->getKey(),
            ];

            $locked->status = OrderStatus::Refunded->value;

            $this->logEvent($locked, 'refunded', $actor, $payload, $from->value, OrderStatus::Refunded->value);
            $this->audit->log('orders.refunded', $locked, ['status' => $from->value], $payload);

            $this->tables->syncForOrder($locked, OrderStatus::Refunded);

            return $locked;
        });
    }

    /* =========================================================
     |  Taşı / birleştir / böl (§12.2)
     * ========================================================= */

    /** Adisyonu başka masaya taşı. */
    public function moveOrder(Order $order, int $targetTableId, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($targetTableId, $actor): Order {
            if (! $locked->isOpen()) {
                throw ValidationException::withMessages(['order' => ['Kapalı adisyon taşınamaz.']]);
            }

            $target = $this->resolveTargetTable($locked, $targetTableId);
            $oldTableId = $locked->table_id;

            if ((int) $oldTableId === (int) $target->getKey()) {
                throw ValidationException::withMessages(['table_id' => ['Adisyon zaten bu masada.']]);
            }

            $locked->table_id = $target->getKey();

            if (! $locked->channelEnum()->usesTable()) {
                $locked->channel = OrderChannel::Table->value; // paket → masaya alma senaryosu
            }

            $this->logEvent($locked, 'order_moved', $actor, [
                'from_table_id' => $oldTableId,
                'to_table_id' => $target->getKey(),
                'to_table' => $target->name,
            ]);

            // Önce taşınmış hâli kalıcılaştır (sync DB'den okur), sonra
            // eski + yeni masa durumlarını güncelle.
            $locked->save();

            if ($oldTableId !== null) {
                $oldTable = Table::withoutTenancy()->find($oldTableId);
                if ($oldTable !== null) {
                    $this->tables->sync($oldTable);
                }
            }

            $this->tables->syncForOrder($locked);

            return $locked;
        });
    }

    /** Kalemi başka masaya taşı (hedefte açık adisyon yoksa açılır). */
    public function moveItem(Order $order, OrderItem $item, int $targetTableId, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($item, $targetTableId, $actor): Order {
            $this->assertItemsChangeable($locked);
            $item = $this->freshItem($locked, $item);

            if (! $item->isActive()) {
                throw ValidationException::withMessages(['item' => ['İptal edilmiş kalem taşınamaz.']]);
            }

            $target = $this->resolveTargetTable($locked, $targetTableId);

            if ((int) $locked->table_id === (int) $target->getKey()) {
                throw ValidationException::withMessages(['table_id' => ['Kalem zaten bu masada.']]);
            }

            $targetOrder = $this->openOrderForTable($locked, $target, $actor);

            /** @var Order $lockedTarget */
            $lockedTarget = Order::query()->lockForUpdate()->findOrFail($targetOrder->getKey());

            $item->order_id = $lockedTarget->getKey();
            $item->save();

            $this->logEvent($locked, 'item_moved_out', $actor, [
                'name' => $item->name,
                'to_order_id' => $lockedTarget->getKey(),
                'to_table' => $target->name,
            ]);
            $this->logEvent($lockedTarget, 'item_moved_in', $actor, [
                'name' => $item->name,
                'from_order_id' => $locked->getKey(),
            ], item: $item);

            $this->recomputeTotals($locked);
            $this->recomputeTotals($lockedTarget);
            $lockedTarget->version = (int) $lockedTarget->version + 1;
            $lockedTarget->save();

            $this->deriveKitchenStatus($locked, $actor);
            $this->deriveKitchenStatus($lockedTarget, $actor);

            // Son kalem taşındıysa kaynak adisyon boş kaldı → otomatik kapat.
            $this->closeIfEmptied($locked, $actor);

            $this->tables->syncForOrder($locked);
            $this->tables->syncForOrder($lockedTarget);

            return $lockedTarget;
        });
    }

    /** İki adisyonu birleştir: source'un kalemleri target'a akar, source kapanır. */
    public function merge(Order $target, Order $source, User $actor, ?int $expectedVersion = null): Order
    {
        if ((int) $target->getKey() === (int) $source->getKey()) {
            throw ValidationException::withMessages(['source_order_id' => ['Adisyon kendisiyle birleştirilemez.']]);
        }

        return $this->withLockedOrder($target, $expectedVersion, function (Order $lockedTarget) use ($source, $actor): Order {
            /** @var Order $lockedSource */
            $lockedSource = Order::query()->lockForUpdate()->findOrFail($source->getKey());

            $this->assertItemsChangeable($lockedTarget);

            if (! $lockedSource->isOpen()) {
                throw ValidationException::withMessages(['source_order_id' => ['Kapalı adisyon birleştirilemez.']]);
            }

            if ((int) $lockedSource->paid_minor > 0) {
                throw ValidationException::withMessages(['source_order_id' => ['Kısmi ödemesi olan adisyon birleştirilemez; önce ödemeyi kapatın.']]);
            }

            $moved = 0;

            foreach ($lockedSource->items as $item) {
                $item->order_id = $lockedTarget->getKey();
                $item->save();
                $moved++;
            }

            $from = $lockedSource->statusEnum();
            $lockedSource->status = OrderStatus::Cancelled->value;
            $lockedSource->cancel_reason = 'Adisyon #'.$lockedTarget->getKey().' ile birleştirildi';
            $lockedSource->cancelled_by_id = $actor->getKey();
            $lockedSource->cancelled_at = now();
            $lockedSource->closed_at = now();
            $this->recomputeTotals($lockedSource);
            $lockedSource->version = (int) $lockedSource->version + 1;
            $lockedSource->save();

            $this->logEvent($lockedSource, 'merged_into', $actor, ['target_order_id' => $lockedTarget->getKey(), 'moved_items' => $moved], $from->value, OrderStatus::Cancelled->value);
            $this->logEvent($lockedTarget, 'merged_from', $actor, ['source_order_id' => $lockedSource->getKey(), 'moved_items' => $moved]);

            $this->recomputeTotals($lockedTarget);
            $this->deriveKitchenStatus($lockedTarget, $actor);

            $this->tables->syncForOrder($lockedSource);
            $this->tables->syncForOrder($lockedTarget);

            return $lockedTarget;
        });
    }

    /**
     * ÜRÜN BAZLI bölme: seçilen kalemler aynı masada YENİ adisyona ayrılır
     * (ayrı hesap ödeyecek grup). Toplamlar kuruşu kuruşuna korunur —
     * kalemler taşınır, yeniden hesaplanmaz.
     *
     * @param  array<int, int>  $itemIds
     */
    public function splitByItems(Order $order, array $itemIds, User $actor, ?int $expectedVersion = null): Order
    {
        return $this->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($itemIds, $actor): Order {
            $this->assertItemsChangeable($locked);

            $items = $locked->items()->whereIn('id', $itemIds)->get()
                ->filter(fn (OrderItem $i): bool => $i->isActive());

            if ($items->isEmpty()) {
                throw ValidationException::withMessages(['item_ids' => ['Bölünecek kalem seçilmedi.']]);
            }

            if ($items->count() >= $locked->items()->get()->filter(fn (OrderItem $i) => $i->isActive())->count()) {
                throw ValidationException::withMessages(['item_ids' => ['Tüm kalemler seçilemez; adisyonda en az bir kalem kalmalı.']]);
            }

            $newOrder = new Order([
                'status' => $locked->status,
                'channel' => $locked->channel,
                'note' => $locked->note,
            ]);
            $newOrder->tenant_id = $locked->tenant_id;
            $newOrder->branch_id = $locked->branch_id;
            $newOrder->table_id = $locked->table_id;
            $newOrder->opened_by_id = $actor->getKey();
            $newOrder->placed_at = $locked->placed_at;
            $newOrder->save();

            foreach ($items as $item) {
                $item->order_id = $newOrder->getKey();
                $item->save();
            }

            $this->logEvent($locked, 'split_out', $actor, ['new_order_id' => $newOrder->getKey(), 'item_count' => $items->count()]);
            $this->logEvent($newOrder, 'split_from', $actor, ['source_order_id' => $locked->getKey(), 'item_count' => $items->count()]);

            $this->recomputeTotals($locked);
            $this->recomputeTotals($newOrder);
            $this->deriveKitchenStatus($locked, $actor);
            $this->deriveKitchenStatus($newOrder, $actor);
            $newOrder->save();
            $this->tables->syncForOrder($locked);

            return $newOrder;
        });
    }

    /**
     * EŞİT / KİŞİ BAZLI bölme: fiziksel taşıma yapmaz; ödeme paylarını
     * kuruş kaybı OLMADAN hesaplar (kalan kuruşlar ilk paylara +1 dağıtılır)
     * ve olay günlüğüne yazar. Payment fazı bu payları tahsil eder.
     *
     * @param  array{mode: 'equal'|'persons', ways?: int, amounts?: array<int, int>}  $data
     * @return array<int, int> kuruş cinsinden paylar
     */
    public function splitShares(Order $order, array $data, User $actor): array
    {
        $total = max(0, (int) $order->total_minor - (int) $order->paid_minor);

        if ($total <= 0) {
            throw ValidationException::withMessages(['split' => ['Bölünecek kalan tutar yok.']]);
        }

        if ($data['mode'] === 'equal') {
            $ways = (int) ($data['ways'] ?? 0);

            if ($ways < 2 || $ways > 50) {
                throw ValidationException::withMessages(['ways' => ['Kişi sayısı 2–50 aralığında olmalı.']]);
            }

            $base = intdiv($total, $ways);
            $remainder = $total - ($base * $ways);

            $shares = array_fill(0, $ways, $base);

            for ($i = 0; $i < $remainder; $i++) {
                $shares[$i]++; // kuruş kaybı yok: kalan kuruşlar ilk paylara
            }
        } else {
            $shares = array_map('intval', $data['amounts'] ?? []);

            if (count($shares) < 2) {
                throw ValidationException::withMessages(['amounts' => ['En az iki pay girilmeli.']]);
            }

            if (array_sum($shares) !== $total || min($shares) < 0) {
                throw ValidationException::withMessages(['amounts' => [
                    'Payların toplamı kalan tutara eşit olmalı ('.Money::toDecimalString($total).' TL).',
                ]]);
            }
        }

        $this->logEvent($order, 'split_shares', $actor, [
            'mode' => $data['mode'],
            'shares_minor' => $shares,
            'total_minor' => $total,
        ]);

        return $shares;
    }

    /* =========================================================
     |  Boşalan adisyonun otomatik kapanışı (kural)
     * ========================================================= */

    /**
     * KURAL: Açık adisyonun TÜM kalemleri kaldırılır/iptal edilir/taşınırsa
     * adisyon otomatik iptal edilir (denetim kaydıyla) ve masa durumu
     * yeniden türetilir → başka açık adisyon yoksa masa Boş'a döner.
     * Rezerve / Kullanım dışı masalar TableStatusSynchronizer'da ezilmez.
     *
     * Yalnız kalem-çıkaran yollardan (removeItem/cancelItem/moveItem)
     * çağrılır; yeni açılmış (henüz kalem eklenmemiş) adisyona dokunmaz.
     * Tahsilatı olan adisyon kapatılmaz (iade yolu kullanılmalı).
     */
    /**
     * Kural dışı kalmış (boş ama açık) adisyonu kilit altında kapatır.
     * Onarım komutu (orders:repair-table-status) kullanır.
     *
     * @return bool adisyon bu çağrıda kapatıldı mı
     */
    public function autoCloseIfEmpty(Order $order, ?User $actor = null): bool
    {
        return $this->withLockedOrder($order, null, function (Order $locked) use ($actor): bool {
            $before = (string) $locked->status;
            $this->closeIfEmptied($locked, $actor);

            return (string) $locked->status !== $before;
        });
    }

    private function closeIfEmptied(Order $locked, ?User $actor): void
    {
        if (! $locked->statusEnum()->isOpen() || (int) $locked->paid_minor > 0) {
            return;
        }

        $hasActiveItem = $locked->items()->get()
            ->contains(fn (OrderItem $i): bool => $i->isActive());

        if ($hasActiveItem) {
            return;
        }

        $from = $locked->statusEnum();

        $locked->status = OrderStatus::Cancelled->value;
        $locked->cancel_reason = 'Tüm kalemler kaldırıldı — adisyon otomatik kapatıldı';
        $locked->cancelled_by_id = $actor?->getKey();
        $locked->cancelled_at = now();
        $locked->closed_at = now();

        $payload = [
            'reason' => $locked->cancel_reason,
            'performed_by' => $actor?->getKey(),
        ];

        $this->logEvent($locked, 'auto_closed_empty', $actor, $payload, $from->value, OrderStatus::Cancelled->value);
        $this->audit->log('orders.auto_closed_empty', $locked, ['status' => $from->value], $payload);

        $this->tables->syncForOrder($locked, OrderStatus::Cancelled);
    }

    /* =========================================================
     |  Tutar hesabı — TEK yer (ADR-007)
     * ========================================================= */

    /** Satır brütü: qty × (birim + seçenekler), indirim DÜŞÜLMEDEN. */
    private function lineGross(OrderItem $item): int
    {
        return (int) $item->qty * ((int) $item->unit_price_minor + (int) $item->options_price_minor);
    }

    /** Satır toplam + KDV payı. İkram/iptal satır toplamı 0'dır. */
    private function computeLine(OrderItem $item): void
    {
        if (! $item->isActive() || $item->is_comp) {
            $item->line_total_minor = 0;
            $item->vat_minor = 0;

            return;
        }

        $gross = $this->lineGross($item);
        $total = max(0, $gross - (int) $item->discount_minor);

        $item->line_total_minor = $total;
        $item->vat_minor = Money::vatPortionOfGross($total, (float) $item->tax_rate);
    }

    /** Adisyon dökümü: kalemlerden yukarı; sipariş indirimi en sonda. */
    private function recomputeTotals(Order $order): void
    {
        $items = $order->items()->get();

        $itemsTotal = 0;
        $compTotal = 0;
        $vatTotal = 0;

        foreach ($items as $item) {
            if (! $item->isActive()) {
                continue;
            }

            if ($item->is_comp) {
                $compTotal += $this->lineGross($item);

                continue;
            }

            $itemsTotal += (int) $item->line_total_minor;
            $vatTotal += (int) $item->vat_minor;
        }

        // Yüzdeli sipariş indirimi kalem toplamı değiştikçe yeniden hesaplanır.
        if ($order->discount_percent !== null) {
            $order->discount_minor = Money::percent($itemsTotal, (float) $order->discount_percent);
        }

        $discount = min((int) $order->discount_minor, $itemsTotal);

        // Yüzdeli servis bedeli (Faz-5) kalem toplamı değiştikçe yeniden hesaplanır.
        if ($order->service_charge_percent !== null) {
            $order->service_charge_minor = Money::percent($itemsTotal - $discount, (float) $order->service_charge_percent);
        }

        $order->items_total_minor = $itemsTotal;
        $order->comp_total_minor = $compTotal;
        $order->vat_total_minor = $vatTotal;
        $order->discount_minor = $discount;
        $order->total_minor = max(0, $itemsTotal - $discount
            + (int) ($order->service_charge_minor ?? 0)
            + (int) ($order->rounding_minor ?? 0));
    }

    /* =========================================================
     |  Yardımcılar
     * ========================================================= */

    private function assertItemsChangeable(Order $order): void
    {
        if (! $order->statusEnum()->allowsItemChanges()) {
            throw ValidationException::withMessages(['order' => [
                'Kapalı adisyonda değişiklik yapılamaz (durum: '.$order->statusEnum()->label().').',
            ]]);
        }
    }

    /** Kalem gerçekten bu adisyonun ve bu kiracının mı? */
    private function freshItem(Order $order, OrderItem $item): OrderItem
    {
        $fresh = $order->items()->lockForUpdate()->find($item->getKey());

        if ($fresh === null) {
            throw ValidationException::withMessages(['item' => ['Kalem bu adisyonda bulunamadı.']]);
        }

        return $fresh;
    }

    private function resolveTargetTable(Order $order, int $tableId): Table
    {
        $table = Table::withoutTenancy()
            ->where('tenant_id', $order->tenant_id)
            ->where('branch_id', $order->branch_id)
            ->find($tableId);

        if ($table === null || ! $table->is_active) {
            throw ValidationException::withMessages(['table_id' => ['Hedef masa bu şubede bulunamadı.']]);
        }

        return $table;
    }

    /** Hedef masadaki açık adisyon; yoksa yeni açılır. */
    private function openOrderForTable(Order $context, Table $table, User $actor): Order
    {
        $existing = Order::withoutTenancy()
            ->where('tenant_id', $context->tenant_id)
            ->where('table_id', $table->getKey())
            ->whereNotIn('status', [OrderStatus::Paid->value, OrderStatus::Cancelled->value, OrderStatus::Refunded->value])
            ->orderByDesc('id')
            ->first();

        if ($existing !== null) {
            return $existing;
        }

        $order = new Order([
            'status' => OrderStatus::Placed->value,
            'channel' => OrderChannel::Table->value,
        ]);
        $order->tenant_id = $context->tenant_id;
        $order->branch_id = $context->branch_id;
        $order->table_id = $table->getKey();
        $order->opened_by_id = $actor->getKey();
        $order->placed_at = now();
        $order->save();

        $this->logEvent($order, 'opened', $actor, ['channel' => OrderChannel::Table->value, 'via' => 'item_move'], null, OrderStatus::Placed->value);

        return $order;
    }

    private function channelUnitPrice(Product $product, OrderChannel $channel): int
    {
        $column = $channel->priceColumn();

        if ($column !== null && $product->{$column} !== null) {
            return (int) $product->{$column};
        }

        if ($product->discounted_price_minor !== null) {
            return (int) $product->discounted_price_minor;
        }

        return (int) $product->price_minor;
    }

    /**
     * Seçenekler ürünün bağlı gruplarında olmalı; grup kuralları
     * (zorunlu / min–max seçim) doğrulanır.
     *
     * FİYAT KURALI (free_limit — "N adet ücretsiz"): grup içinde seçilen
     * seçenekler fiyata göre BÜYÜKTEN küçüğe sıralanır; ilk `free_limit`
     * tanesi ÜCRETSİZDİR (müşteri lehine: en pahalılar bedava), kalanlar
     * kendi fiyatından ücretlendirilir. Snapshot'a seçenek başına
     * EFEKTİF fiyat yazılır (ücretsiz olan 0) — adisyon sonradan değişmez.
     *
     * @param  array<int, int>  $optionIds
     * @return array<int, array{0: \App\Modules\Catalog\Models\OptionGroup, 1: Option, 2: int}> [grup, seçenek, efektif kuruş]
     */
    private function resolveOptions(Product $product, array $optionIds): array
    {
        $optionIds = array_values(array_unique($optionIds));
        $rows = [];

        foreach ($product->optionGroups as $group) {
            $selected = $group->options
                ->filter(fn (Option $o): bool => $o->is_active && in_array((int) $o->getKey(), $optionIds, true));

            // free_limit: fiyatı yüksek olandan başlayarak N seçenek ücretsiz.
            $freeLimit = max(0, (int) $group->free_limit);
            $ranked = $selected->sortByDesc(fn (Option $o): int => (int) $o->price_minor)->values();

            foreach ($ranked as $index => $option) {
                $effective = $index < $freeLimit ? 0 : (int) $option->price_minor;
                $rows[] = [$group, $option, $effective];
            }

            $count = $selected->count();
            $min = $group->is_required ? max(1, (int) $group->min_select) : (int) $group->min_select;

            if ($group->is_required && $count < $min) {
                throw ValidationException::withMessages(['option_ids' => [
                    sprintf('"%s" için en az %d seçim zorunlu.', $group->name, $min),
                ]]);
            }

            if ($count > 0 && $group->selection_type === 'single' && $count > 1) {
                throw ValidationException::withMessages(['option_ids' => [
                    sprintf('"%s" için tek seçim yapılabilir.', $group->name),
                ]]);
            }

            if ($group->max_select !== null && $count > (int) $group->max_select) {
                throw ValidationException::withMessages(['option_ids' => [
                    sprintf('"%s" için en fazla %d seçim yapılabilir.', $group->name, (int) $group->max_select),
                ]]);
            }
        }

        // Ürüne bağlı olmayan seçenek id'si sızdırılamaz.
        if (count($rows) !== count($optionIds)) {
            throw ValidationException::withMessages(['option_ids' => ['Seçeneklerden bazıları bu ürüne ait değil.']]);
        }

        return $rows;
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function logEvent(Order $order, string $type, ?User $actor, array $payload = [], ?string $from = null, ?string $to = null, ?OrderItem $item = null): void
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

    /* =========================================================
     |  Public (QR) sipariş — Musteri-Menu ajanı bu uca bağlanır
     * ========================================================= */

    /**
     * Masadaki müşterinin QR siparişi: kiracı YALNIZ token'dan çözülür
     * (ADR-008), sipariş "Onay bekliyor" açılır, garson panelde onaylar.
     *
     * @param  array{note?: string|null, customer_name?: string|null,
     *   items: array<int, array{product_id: int, variant_id?: int|null, qty: int, option_ids?: array<int, int>, note?: string|null}>}  $data
     */
    public function createPublicOrder(Table $table, array $data): Order
    {
        return DB::transaction(function () use ($table, $data): Order {
            $order = new Order([
                'status' => OrderStatus::PendingApproval->value,
                'channel' => OrderChannel::Qr->value,
                'note' => $data['note'] ?? null,
                'customer_name' => $data['customer_name'] ?? null,
            ]);
            $order->tenant_id = $table->tenant_id;
            $order->branch_id = $table->branch_id;
            $order->table_id = $table->getKey();
            $order->public_token = Order::generatePublicToken();
            $order->save();

            foreach ($data['items'] as $itemData) {
                $this->buildItem($order, $itemData, null);
            }

            $this->recomputeTotals($order);
            $order->save();

            $this->logEvent($order, 'opened', null, ['channel' => OrderChannel::Qr->value, 'source' => 'public'], null, OrderStatus::PendingApproval->value);

            $this->tables->syncForOrder($order);

            return $order;
        });
    }
}
