<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Support\Qty;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Sipariş ↔ stok köprüsü (§17 madde 5).
 *
 * TETİK: Orders modülüne DOKUNMADAN, OrderItem/Order Eloquent model
 * olaylarından (InventoryServiceProvider::boot) beslenir:
 *   - kalem `served` olduğunda → o kalemin reçete tüketimi düşer
 *     (yemek fiziksel olarak mutfaktan çıkmıştır; ödeme beklenmez),
 *   - sipariş `paid` olduğunda → henüz düşülmemiş aktif kalemler düşer
 *     (güvenlik ağı: servis işaretlenmeden kapatılan adisyonlar).
 *
 * KURALLAR:
 *   - Kalem başına İDEMPOTENT: defterde ref(order_item, id) satırı varsa
 *     ikinci kez düşülmez (served + paid çifte tetikte çift düşüm olmaz).
 *   - İkram kalemleri comp_consumption türüyle düşer (§17.4 listesi).
 *   - Reçete yoksa hareket YAZILMAZ; ürün uyarı panosunda "reçetesiz
 *     satış" olarak listelenir (AlertService).
 *   - Stok hatası SERVİSİ DURDURMAZ: istisna yutulur ve report() edilir
 *     (adisyon transaction'ı stok yüzünden geri sarılmaz).
 */
class ConsumptionService
{
    public function __construct(
        private readonly RecipeService $recipes,
        private readonly StockLedger $ledger,
    ) {
    }

    /** Model olayından güvenli çağrı (asla fırlatmaz). */
    public function safeConsumeOrderItem(OrderItem $item): void
    {
        try {
            $this->consumeOrderItem($item);
        } catch (\Throwable $e) {
            report($e); // stok kaydı düşemedi; sipariş akışı ETKİLENMEZ
        }
    }

    /** Model olayından güvenli çağrı (asla fırlatmaz). */
    public function safeConsumeOrder(Order $order): void
    {
        try {
            foreach ($order->items()->get() as $item) {
                if ($item->isActive()) {
                    $this->consumeOrderItem($item);
                }
            }
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * Kalemin reçete tüketimini deftere işler (idempotent).
     *
     * @return array<int, StockMovement> yazılan hareketler (reçete yoksa boş)
     */
    public function consumeOrderItem(OrderItem $item): array
    {
        if (! $item->isActive() || $item->product_id === null) {
            return [];
        }

        return DB::transaction(function () use ($item): array {
            // İdempotens: bu kalem için tüketim zaten defterdeyse çık.
            $already = StockMovement::withoutTenancy()
                ->where('tenant_id', $item->tenant_id)
                ->where('ref_type', 'order_item')
                ->where('ref_id', $item->getKey())
                ->exists();

            if ($already) {
                return [];
            }

            $order = $item->order()->withoutGlobalScopes()->first();

            if ($order === null) {
                return [];
            }

            $recipe = $this->recipes->resolveForSale(
                (int) $item->tenant_id,
                (int) $item->product_id,
                $item->variant_id !== null ? (int) $item->variant_id : null,
                $order->branch_id !== null ? (int) $order->branch_id : null,
            );

            if ($recipe === null) {
                return []; // reçetesiz ürün — uyarı panosu yakalar
            }

            $type = $item->is_comp ? MovementType::CompConsumption : MovementType::RecipeConsumption;
            $defaultWarehouse = Warehouse::defaultFor((int) $item->tenant_id, $order->branch_id !== null ? (int) $order->branch_id : null);
            $movements = [];

            foreach ($recipe->lines as $line) {
                $component = StockItem::withoutTenancy()
                    ->where('tenant_id', $item->tenant_id)
                    ->find($line->item_id);

                if ($component === null || ! $component->is_active) {
                    continue;
                }

                // 1 porsiyon × adet, satır ve reçete fireleri uygulanır.
                $qty = (int) $line->qty_milli * (int) $item->qty;
                $qty = Qty::withPercent($qty, (float) $line->waste_percent);
                $qty = Qty::withPercent($qty, (float) $recipe->waste_percent);

                if ($qty <= 0) {
                    continue;
                }

                $warehouse = null;

                if ($line->warehouse_id !== null) {
                    $warehouse = Warehouse::withoutTenancy()
                        ->where('tenant_id', $item->tenant_id)
                        ->find($line->warehouse_id);
                }

                $warehouse ??= $defaultWarehouse;

                if ($warehouse === null) {
                    continue; // hiç depo tanımlanmamış — düşülecek yer yok
                }

                $movements[] = $this->ledger->record([
                    'type' => $type,
                    'item' => $component,
                    'warehouse' => $warehouse,
                    'qty_milli' => -$qty,
                    'tenant_id' => (int) $item->tenant_id,
                    'branch_id' => $order->branch_id,
                    'unit_cost_minor' => (int) $component->avg_cost_minor,
                    'ref_type' => 'order_item',
                    'ref_id' => $item->getKey(),
                    'description' => sprintf('Adisyon #%d — %s ×%d (reçete v%d)', $order->getKey(), $item->name, $item->qty, $recipe->version),
                ]);
            }

            return $movements;
        });
    }

    /**
     * Yarı mamul üretimi: hedef kalem stoğa GİRER, reçetesindeki bileşenler
     * DÜŞER (üretim miktarı verimle oranlanır).
     *
     * @return array{production: StockMovement, consumed: array<int, StockMovement>}
     */
    public function produce(StockItem $target, int $qtyMilli, Warehouse $warehouse, ?User $user): array
    {
        if (! $target->is_semi_finished) {
            throw ValidationException::withMessages(['item' => ['Yalnız yarı mamul kalemler üretilebilir.']]);
        }

        if ($qtyMilli <= 0) {
            throw ValidationException::withMessages(['qty' => ['Üretim miktarı pozitif olmalı.']]);
        }

        $recipe = \App\Modules\Inventory\Models\Recipe::withoutTenancy()
            ->with('lines')
            ->where('tenant_id', $target->tenant_id)
            ->where('item_id', $target->getKey())
            ->where('is_active', true)
            ->first();

        if ($recipe === null) {
            throw ValidationException::withMessages(['item' => ['Bu yarı mamulün aktif reçetesi yok.']]);
        }

        return DB::transaction(function () use ($target, $qtyMilli, $warehouse, $user, $recipe): array {
            $yield = max(1, (int) $recipe->yield_qty_milli);

            // 1. geçiş: bileşen miktar + maliyet planı (defter yazımı YOK —
            // defter satırları sonradan güncellenmez, önce plan kurulur).
            $plan = [];
            $componentCost = 0;

            foreach ($recipe->lines as $line) {
                $component = StockItem::withoutTenancy()
                    ->where('tenant_id', $target->tenant_id)->find($line->item_id);

                if ($component === null) {
                    continue;
                }

                // Verim başına satır miktarı × üretilen miktar.
                $qty = (int) round((int) $line->qty_milli * $qtyMilli / $yield, 0, PHP_ROUND_HALF_UP);
                $qty = Qty::withPercent($qty, (float) $line->waste_percent);
                $qty = Qty::withPercent($qty, (float) $recipe->waste_percent);

                if ($qty <= 0) {
                    continue;
                }

                $plan[] = ['component' => $component, 'qty' => $qty];
                $componentCost += Qty::cost($qty, (int) $component->avg_cost_minor);
            }

            // Üretilen yarı mamulün birim maliyeti = bileşen maliyeti / miktar.
            $unitCost = $qtyMilli > 0
                ? (int) round($componentCost * 1000 / $qtyMilli, 0, PHP_ROUND_HALF_UP)
                : 0;

            $production = $this->ledger->record([
                'type' => MovementType::Production,
                'item' => $target,
                'warehouse' => $warehouse,
                'qty_milli' => $qtyMilli,
                'tenant_id' => (int) $target->tenant_id,
                'unit_cost_minor' => $unitCost,
                'ref_type' => 'production',
                'description' => sprintf('Üretim — reçete v%d', $recipe->version),
                'user' => $user,
            ]);

            // 2. geçiş: bileşen düşümleri üretim satırına bağlı yazılır.
            $consumed = [];

            foreach ($plan as $row) {
                $consumed[] = $this->ledger->record([
                    'type' => MovementType::RecipeConsumption,
                    'item' => $row['component'],
                    'warehouse' => $warehouse,
                    'qty_milli' => -$row['qty'],
                    'tenant_id' => (int) $target->tenant_id,
                    'unit_cost_minor' => (int) $row['component']->avg_cost_minor,
                    'ref_type' => 'production',
                    'ref_id' => $production->getKey(),
                    'description' => sprintf('%s üretimi (%s %s)', $target->name, Qty::toDecimalString($qtyMilli), $target->base_unit),
                    'user' => $user,
                ]);
            }

            return ['production' => $production, 'consumed' => $consumed];
        });
    }
}
