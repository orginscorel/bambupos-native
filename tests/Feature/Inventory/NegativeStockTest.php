<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Services\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * NEGATİF STOK KORUMASI: manuel çıkışlar eksiye düşemez; satış/reçete
 * tüketimi düşebilir (servis durmaz) ve uyarı panosuna düşer.
 */
class NegativeStockTest extends TestCase
{
    use InteractsWithInventory, InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    public function test_manuel_cikis_stogu_eksiye_dusuremez(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 1_000, 500); // 1 kg

        // API: 2 kg fire → 422; seviye değişmez.
        $this->postJson('/api/v1/inventory/movements', [
            'warehouse_id' => $warehouse->id,
            'item_id' => $item->id,
            'type' => 'waste',
            'qty' => '2',
            'description' => 'Bozulma',
        ])->assertUnprocessable();

        $this->assertSame(1_000, $this->onHandMilli($item, $warehouse));
    }

    public function test_transfer_kaynak_depoyu_eksiye_dusuremez(): void
    {
        $from = $this->makeWarehouse($this->a, ['name' => 'Ana Depo T', 'is_default' => true]);
        $to = $this->makeWarehouse($this->a, ['name' => 'Mutfak T', 'type' => 'kitchen', 'is_default' => false]);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $from, 500, 100);

        $this->postJson('/api/v1/inventory/transfers', [
            'item_id' => $item->id,
            'from_warehouse_id' => $from->id,
            'to_warehouse_id' => $to->id,
            'qty' => '1', // 1 kg > 0,5 kg
        ])->assertUnprocessable();

        $this->assertSame(500, $this->onHandMilli($item, $from));
        $this->assertSame(0, $this->onHandMilli($item, $to));
    }

    public function test_recete_tuketimi_eksiye_dusebilir_ve_uyari_panosuna_duser(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a, ['name' => 'Kritik Malzeme']);
        $this->seedStock($item, $warehouse, 100, 1_000); // yalnız 100 g var

        // 300 g tüketim — mutfak akışı DURMAZ, stok -200 olur.
        app(StockLedger::class)->record([
            'type' => MovementType::RecipeConsumption,
            'item' => $item->fresh(),
            'warehouse' => $warehouse,
            'qty_milli' => -300,
            'tenant_id' => (int) $item->tenant_id,
            'description' => 'Satış tüketimi',
        ]);

        $this->assertSame(-200, $this->onHandMilli($item, $warehouse));

        $alerts = $this->getJson('/api/v1/inventory/alerts')->assertOk()->json('alerts');
        $this->assertNotEmpty($alerts['negative']);
        $this->assertSame('Kritik Malzeme', $alerts['negative'][0]['name']);
    }

    public function test_defter_cekirdegi_de_manuel_turlerde_eksiyi_reddeder(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 1_000, 500);

        $this->expectException(ValidationException::class);

        app(StockLedger::class)->record([
            'type' => MovementType::Loss,
            'item' => $item->fresh(),
            'warehouse' => $warehouse,
            'qty_milli' => -5_000,
            'tenant_id' => (int) $item->tenant_id,
            'description' => 'Zayi',
        ]);
    }
}
