<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Supplier;
use App\Modules\Inventory\Models\SupplierPrice;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * SATIN ALMA (§17.6): talep→sipariş→mal kabul→iade + ortalama maliyet,
 * fiyat geçmişi, önerilen sipariş.
 */
class PurchasingTest extends TestCase
{
    use InteractsWithInventory, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    private function makeSupplier(array $attrs = []): Supplier
    {
        return $this->asTenant($this->a['tenant'], function () use ($attrs): Supplier {
            $s = new Supplier(array_merge(['name' => 'Tedarikçi '.fake()->unique()->numerify('###'), 'payment_term_days' => 30, 'is_active' => true], $attrs));
            $s->save();

            return $s;
        });
    }

    public function test_tam_akis_mal_kabul_ortalama_maliyet_fiyat_gecmisi(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a, ['name' => 'Zeytinyağı', 'base_unit' => 'lt', 'sub_unit' => 'ml']);
        $supplier = $this->makeSupplier();

        // Elde 10 lt × 100,00 TL ortalama.
        $this->seedStock($item, $warehouse, 10_000, 10_000);

        $poId = $this->postJson('/api/v1/inventory/purchases', [
            'supplier_id' => $supplier->id,
            'warehouse_id' => $warehouse->id,
            'lines' => [['item_id' => $item->id, 'qty' => '10', 'unit_price' => '130']], // 10 lt × 130 TL
        ])->assertCreated()->json('order.id');

        // Talep → sipariş (vade tedarikçiden türetilir: 30 gün).
        $order = $this->postJson("/api/v1/inventory/purchases/{$poId}/transition", ['status' => 'ordered'])
            ->assertOk()->json('order');
        $this->assertSame('ordered', $order['status']);
        $this->assertNotNull($order['due_date']);

        // KISMİ mal kabul: 4 lt.
        $lineId = $order['lines'][0]['id'];
        $partial = $this->postJson("/api/v1/inventory/purchases/{$poId}/receive", [
            'lines' => [['line_id' => $lineId, 'qty' => '4', 'lot_no' => 'LOT-1', 'expires_at' => now()->addMonths(6)->toDateString()]],
        ])->assertOk()->json('order');

        $this->assertSame('partially_received', $partial['status']);
        $this->assertSame(14_000, $this->onHandMilli($item, $warehouse));

        // Hareketli ortalama: (10×10000 + 4×13000) / 14 = 10857 kuruş (half-up).
        $this->assertSame(10_857, (int) $item->fresh()->avg_cost_minor);
        $this->assertSame(13_000, (int) $item->fresh()->last_cost_minor);

        // Kalan 6 lt → tam teslim.
        $full = $this->postJson("/api/v1/inventory/purchases/{$poId}/receive", [
            'lines' => [['line_id' => $lineId, 'qty' => '6']],
        ])->assertOk()->json('order');

        $this->assertSame('received', $full['status']);
        $this->assertSame(20_000, $this->onHandMilli($item, $warehouse));

        // Fiyat geçmişi yazıldı.
        $this->assertSame(2, SupplierPrice::withoutTenancy()->where('supplier_id', $supplier->id)->where('item_id', $item->id)->count());

        // Fazla teslim REDDEDİLİR.
        $this->postJson("/api/v1/inventory/purchases/{$poId}/receive", [
            'lines' => [['line_id' => $lineId, 'qty' => '1']],
        ])->assertUnprocessable();

        // Tedarikçiye iade: 2 lt çıkış.
        $this->postJson("/api/v1/inventory/purchases/{$poId}/return", [
            'reason' => 'Hasarlı ambalaj',
            'lines' => [['line_id' => $lineId, 'qty' => '2']],
        ])->assertOk();

        $this->assertSame(18_000, $this->onHandMilli($item, $warehouse));
        $this->assertSame(1, StockMovement::withoutTenancy()->where('type', MovementType::PurchaseReturn->value)->count());

        // Fatura + ödeme durumu.
        $invoiced = $this->postJson("/api/v1/inventory/purchases/{$poId}/invoice", [
            'invoice_no' => 'FTR-2026-001',
            'invoice_total' => '1300',
            'paid_amount' => '500',
        ])->assertOk()->json('order');

        $this->assertSame('partial', $invoiced['payment_status']);
        $this->assertSame(130_000, (int) $invoiced['invoice_total_minor']);
    }

    public function test_onerilen_siparis_min_altindaki_kalemleri_tedarikciye_gruplar(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $supplier = $this->makeSupplier(['name' => 'Ana Tedarikçi']);

        $dusuk = $this->makeStockItem($this->a, [
            'name' => 'Azalan Malzeme',
            'min_qty_milli' => 5_000,
            'max_qty_milli' => 20_000,
            'default_supplier_id' => $supplier->id,
        ]);
        $bol = $this->makeStockItem($this->a, ['name' => 'Bol Malzeme', 'min_qty_milli' => 1_000]);

        $this->seedStock($dusuk, $warehouse, 2_000, 1_000); // min 5 kg altında
        $this->seedStock($bol, $warehouse, 9_000, 1_000);   // min üstü

        $suggestions = $this->getJson('/api/v1/inventory/purchases/suggested')->assertOk()->json('suggestions');

        $this->assertCount(1, $suggestions);
        $this->assertSame('Ana Tedarikçi', $suggestions[0]['supplier']['name']);
        $this->assertSame('Azalan Malzeme', $suggestions[0]['items'][0]['name']);
        // Öneri: maks (20 kg) - eldeki (2 kg) = 18 kg.
        $this->assertSame(18_000, (int) $suggestions[0]['items'][0]['suggested_qty_milli']);
    }

    public function test_siparise_gecmis_belgede_satir_degistirilemez(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $supplier = $this->makeSupplier();

        $poId = $this->postJson('/api/v1/inventory/purchases', [
            'supplier_id' => $supplier->id,
            'warehouse_id' => $warehouse->id,
            'lines' => [['item_id' => $item->id, 'qty' => '5', 'unit_price' => '10']],
        ])->assertCreated()->json('order.id');

        $this->postJson("/api/v1/inventory/purchases/{$poId}/transition", ['status' => 'ordered'])->assertOk();

        $this->putJson("/api/v1/inventory/purchases/{$poId}", [
            'lines' => [['item_id' => $item->id, 'qty' => '50', 'unit_price' => '1']],
        ])->assertUnprocessable();
    }
}
