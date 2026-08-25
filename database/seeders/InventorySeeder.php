<?php

namespace Database\Seeders;

use App\Modules\Catalog\Models\Product;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Enums\WarehouseType;
use App\Modules\Inventory\Models\ItemCategory;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\Supplier;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Services\RecipeService;
use App\Modules\Inventory\Services\StockLedger;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

/**
 * DEPO / STOK demo verisi (§17 madde 10): ekranlar dolu ve TUTARLI görünsün.
 *
 *  - 1 varsayılan depo (merkez) + hammadde kategorisi + 1 tedarikçi,
 *  - gerçekçi hammadde/içecek stok kalemleri (kg/lt/adet, kritik eşik,
 *    gramaj için g/ml alt birim),
 *  - demo menüsündeki GERÇEK ürünlere reçete (köfte→dana kıyma 180 g,
 *    burger→kıyma+ekmek+kaşar, patates, çay, latte, soda),
 *  - mal kabul (alış) hareketleriyle başlangıç stoğu + ortalama maliyet,
 *  - birkaç tüketim/fire hareketi (bugün) → hareket defteri + gün sonu
 *    raporu dolu görünür.
 *
 * Idempotent: demo kiracıda inv_items zaten varsa hiçbir şey yazılmaz.
 * Miktar milli-int (ana birim ×1000), para kuruş-int (ADR-007).
 */
class InventorySeeder extends Seeder
{
    public function run(): void
    {
        app(TenantContext::class)->runWithoutTenancy(function (): void {
            $tenant = Tenant::query()->where('slug', 'demo')->first();

            if ($tenant === null) {
                return;
            }

            $tenantId = (int) $tenant->id;

            if (StockItem::withoutTenancy()->where('tenant_id', $tenantId)->exists()) {
                return; // zaten seed'li
            }

            $branchId = (int) (Branch::withoutGlobalScopes()->where('tenant_id', $tenantId)->min('id') ?? 0) ?: null;

            $warehouse = $this->warehouse($tenantId, $branchId);
            $category = $this->category($tenantId, 'Hammadde');
            $beverageCat = $this->category($tenantId, 'İçecek / Hazır');
            $supplier = $this->supplier($tenantId);

            // [ad, base_unit, sub_unit, sub_factor, critical(milli), min(milli), kategori, alış_milli, birim_maliyet_kuruş]
            $items = [
                ['Dana Kıyma', 'kg', 'g', 1000, 5000, 10000, $category, 40000, 32000],
                ['Kaşar Peyniri', 'kg', 'g', 1000, 3000, 6000, $category, 15000, 24000],
                ['Hamburger Ekmeği', 'adet', null, null, 20000, 40000, $category, 120000, 850],
                ['Patates', 'kg', 'g', 1000, 8000, 20000, $category, 60000, 2200],
                ['Çay', 'kg', 'g', 1000, 2000, 4000, $category, 10000, 18000],
                ['Kahve Çekirdeği', 'kg', 'g', 1000, 2000, 5000, $category, 8000, 65000],
                ['Süt', 'lt', 'ml', 1000, 10000, 20000, $beverageCat, 50000, 3200],
                ['Meyveli Soda (Şişe)', 'adet', null, null, 24000, 48000, $beverageCat, 200000, 1500],
            ];

            /** @var array<string, StockItem> $created */
            $created = [];
            $ledger = app(StockLedger::class);

            foreach ($items as [$name, $unit, $sub, $factor, $critical, $min, $cat, $purchaseMilli, $costMinor]) {
                $item = new StockItem([
                    'name' => $name,
                    'base_unit' => $unit,
                    'sub_unit' => $sub,
                    'sub_unit_factor' => $factor,
                    'category_id' => $cat->getKey(),
                    'critical_qty_milli' => $critical,
                    'min_qty_milli' => $min,
                    'default_supplier_id' => $supplier->getKey(),
                    'is_active' => true,
                ]);
                $item->tenant_id = $tenantId;
                $item->save();
                $created[$name] = $item;

                // Mal kabul: "… geldi" — stok girer, ortalama maliyet oturur.
                $ledger->record([
                    'type' => MovementType::Purchase,
                    'item' => $item,
                    'warehouse' => $warehouse,
                    'qty_milli' => (int) $purchaseMilli,
                    'tenant_id' => $tenantId,
                    'branch_id' => $branchId,
                    'unit_cost_minor' => (int) $costMinor,
                    'ref_type' => 'purchase_order',
                    'description' => sprintf('Açılış mal kabulü — %s', $name),
                    'occurred_at' => now()->subDays(3),
                ]);
            }

            $this->recipes($tenantId, $created);
            $this->demoConsumption($tenantId, $branchId, $warehouse, $ledger, $created);
        });
    }

    private function warehouse(int $tenantId, ?int $branchId): Warehouse
    {
        $existing = Warehouse::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('name', 'Merkez Depo')->first();
        if ($existing !== null) {
            return $existing;
        }

        $w = new Warehouse([
            'name' => 'Merkez Depo',
            'code' => 'MRKZ',
            'type' => WarehouseType::Main->value,
            'branch_id' => $branchId,
            'is_default' => true,
            'is_active' => true,
        ]);
        $w->tenant_id = $tenantId;
        $w->save();

        return $w;
    }

    private function category(int $tenantId, string $name): ItemCategory
    {
        $existing = ItemCategory::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('name', $name)->first();
        if ($existing !== null) {
            return $existing;
        }

        $c = new ItemCategory(['name' => $name]);
        $c->tenant_id = $tenantId;
        $c->save();

        return $c;
    }

    private function supplier(int $tenantId): Supplier
    {
        $existing = Supplier::withoutGlobalScopes()->where('tenant_id', $tenantId)->where('name', 'Anadolu Gıda Tedarik')->first();
        if ($existing !== null) {
            return $existing;
        }

        $s = new Supplier([
            'name' => 'Anadolu Gıda Tedarik',
            'contact_name' => 'Satın Alma',
            'phone' => '0312 000 00 00',
            'payment_term_days' => 30,
            'is_active' => true,
        ]);
        $s->tenant_id = $tenantId;
        $s->save();

        return $s;
    }

    /** Demo menüsündeki gerçek ürünlere reçete bağla (gramaj bazlı). */
    private function recipes(int $tenantId, array $items): void
    {
        $svc = app(RecipeService::class);

        // ürün adı (like) => [ [kalem adı, qty_milli], ... ]
        $map = [
            'Izgara Köfte' => [['Dana Kıyma', 180]],
            'Classic Cheeseburger' => [['Dana Kıyma', 150], ['Hamburger Ekmeği', 1000], ['Kaşar Peyniri', 30]],
            'Patates Kızartması' => [['Patates', 200]],
            'Çay (Bardak)' => [['Çay', 5]],
            'Latte' => [['Kahve Çekirdeği', 18], ['Süt', 200]],
            'Meyveli Soda' => [['Meyveli Soda (Şişe)', 1000]],
        ];

        foreach ($map as $productName => $lines) {
            $product = Product::withoutGlobalScopes()
                ->where('tenant_id', $tenantId)
                ->where('name', 'like', $productName.'%')
                ->first();

            if ($product === null) {
                continue;
            }

            $recipeLines = [];

            foreach ($lines as [$itemName, $qtyMilli]) {
                if (! isset($items[$itemName])) {
                    continue;
                }
                $recipeLines[] = ['item_id' => $items[$itemName]->getKey(), 'qty_milli' => (int) $qtyMilli, 'unit_entry' => 'base'];
            }

            if ($recipeLines === []) {
                continue;
            }

            $svc->saveVersion($tenantId, [
                'product_id' => (int) $product->id,
                'lines' => $recipeLines,
                'note' => 'Demo reçete',
            ], null);
        }
    }

    /** Bugüne birkaç tüketim/fire → hareket defteri + gün sonu raporu dolu. */
    private function demoConsumption(int $tenantId, ?int $branchId, Warehouse $warehouse, StockLedger $ledger, array $items): void
    {
        $rows = [
            ['Dana Kıyma', MovementType::RecipeConsumption, 1440, 'Demo satış tüketimi — 8 porsiyon köfte'],
            ['Patates', MovementType::RecipeConsumption, 2000, 'Demo satış tüketimi — 10 porsiyon patates'],
            ['Meyveli Soda (Şişe)', MovementType::Sale, 5000, 'Demo satış — 5 şişe soda'],
            ['Süt', MovementType::RecipeConsumption, 1200, 'Demo satış tüketimi — 6 latte'],
            ['Kaşar Peyniri', MovementType::Waste, 250, 'Fire — bozulan dilim kaşar (demo)'],
        ];

        foreach ($rows as [$name, $type, $qtyMilli, $desc]) {
            if (! isset($items[$name])) {
                continue;
            }

            $ledger->record([
                'type' => $type,
                'item' => $items[$name],
                'warehouse' => $warehouse,
                'qty_milli' => -(int) $qtyMilli,
                'tenant_id' => $tenantId,
                'branch_id' => $branchId,
                'unit_cost_minor' => (int) $items[$name]->avg_cost_minor,
                'description' => $desc,
                'occurred_at' => now()->subHours(2),
            ]);
        }
    }
}
