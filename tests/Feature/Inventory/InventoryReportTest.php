<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Services\ReportService;
use App\Modules\Inventory\Services\StockLedger;
use App\Modules\Inventory\Support\InventoryFeature;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * STOK RAPORU (§17.7): dönem mutabakatı (açılış→giriş→çıkış→kapanış),
 * gün sonu azalma, tüketim maliyeti + feature-flag kancası.
 */
class InventoryReportTest extends TestCase
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

    /** Bugün tüketim düşer (defter üzerinden — imzalı negatif). */
    private function consumeToday($item, $warehouse, int $qtyMilli, MovementType $type = MovementType::RecipeConsumption): void
    {
        app(StockLedger::class)->record([
            'type' => $type,
            'item' => $item,
            'warehouse' => $warehouse,
            'qty_milli' => -$qtyMilli,
            'tenant_id' => (int) $item->tenant_id,
            'unit_cost_minor' => (int) $item->avg_cost_minor,
            'description' => 'Test tüketim',
        ]);
    }

    public function test_donem_mutabakati_acilis_giris_cikis_kapanis_hesaplar(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a, ['name' => 'Dana Kıyma']);

        // Dünkü açılış girişi 10 kg.
        app(StockLedger::class)->record([
            'type' => MovementType::Purchase, 'item' => $item, 'warehouse' => $warehouse,
            'qty_milli' => 10_000, 'tenant_id' => (int) $item->tenant_id, 'unit_cost_minor' => 30_000,
            'occurred_at' => Carbon::now()->subDay(),
        ]);

        // Bugün: +5 kg giriş, -3 kg tüketim.
        app(StockLedger::class)->record([
            'type' => MovementType::Purchase, 'item' => $item->fresh(), 'warehouse' => $warehouse,
            'qty_milli' => 5_000, 'tenant_id' => (int) $item->tenant_id, 'unit_cost_minor' => 30_000,
        ]);
        $this->consumeToday($item->fresh(), $warehouse, 3_000);

        $report = $this->asTenant($this->a['tenant'], fn () => app(ReportService::class)->period(
            (int) $this->a['tenant']->id, Carbon::now()->startOfDay(), Carbon::now()->endOfDay(),
        ));

        $row = collect($report['rows'])->firstWhere('item_id', $item->id);

        $this->assertNotNull($row);
        $this->assertSame(10_000, $row['opening_milli']);   // dünden devir
        $this->assertSame(5_000, $row['in_milli']);         // bugünkü giriş
        $this->assertSame(3_000, $row['out_milli']);        // bugünkü çıkış
        $this->assertSame(12_000, $row['closing_milli']);   // 10 + 5 − 3
        $this->assertSame(90_000, $row['consumed_cost_minor']); // 3 kg × 30000
        $this->assertSame(90_000, $report['totals']['consumed_cost_minor']);
        $this->assertSame(150_000, $report['totals']['in_cost_minor']); // 5 kg × 30000 (bugün giriş)
    }

    public function test_gun_sonu_stoktan_azalan_kalemleri_listeler(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $a = $this->makeStockItem($this->a, ['name' => 'Patates']);
        $b = $this->makeStockItem($this->a, ['name' => 'Süt', 'base_unit' => 'lt']);
        $this->seedStock($a, $warehouse, 20_000, 2_000);
        $this->seedStock($b, $warehouse, 10_000, 3_000);

        $this->consumeToday($a->fresh(), $warehouse, 2_000);
        $this->consumeToday($b->fresh(), $warehouse, 1_500, MovementType::Sale);

        $items = $this->asTenant($this->a['tenant'], fn () => app(ReportService::class)->dayEnd(
            (int) $this->a['tenant']->id, Carbon::now(),
        ));

        $names = collect($items)->pluck('name')->all();
        $this->assertContains('Patates', $names);
        $this->assertContains('Süt', $names);

        $patates = collect($items)->firstWhere('name', 'Patates');
        $this->assertSame(2_000, $patates['used_milli']);
    }

    public function test_rapor_uclari_http_uzerinden_erisilebilir(): void
    {
        $this->getJson('/api/v1/inventory/reports/period?preset=day')
            ->assertOk()->assertJsonStructure(['from', 'to', 'rows', 'totals' => ['in_cost_minor', 'consumed_cost_minor']]);

        $this->getJson('/api/v1/inventory/reports/day-end')
            ->assertOk()->assertJsonStructure(['date', 'items']);

        $this->getJson('/api/v1/inventory/reports/period?preset=month')->assertOk();
    }

    public function test_feature_kancasi_acik_panel_erisilebilir(): void
    {
        $this->assertTrue(InventoryFeature::enabled((int) $this->a['tenant']->id));

        // Feature açık → panel raporu 200.
        $this->get('/panel/stok/rapor')->assertOk();
    }
}
