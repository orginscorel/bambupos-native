<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Services\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use LogicException;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * DEFTERİN DEĞİŞMEZLİĞİ (§17.4): satır güncellenemez / silinemez;
 * anlık stok her zaman defter toplamına eşittir; düzeltme = ters kayıt.
 */
class LedgerImmutabilityTest extends TestCase
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

    public function test_defter_satiri_guncellenemez(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 1_000, 500);

        $movement = StockMovement::withoutTenancy()->firstOrFail();

        $this->expectException(LogicException::class);
        $movement->qty_milli = 999_999;
        $movement->save();
    }

    public function test_defter_satiri_silinemez(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 1_000, 500);

        $movement = StockMovement::withoutTenancy()->firstOrFail();

        $this->expectException(LogicException::class);
        $movement->delete();
    }

    public function test_defter_icin_guncelleme_silme_ucu_yok(): void
    {
        // Rota tablosunda inv movements için PUT/DELETE tanımlı DEĞİL:
        // /movements/{id} diye bir URI hiç yok → 404.
        $this->putJson('/api/v1/inventory/movements/1', [])->assertNotFound();
        $this->deleteJson('/api/v1/inventory/movements/1')->assertNotFound();
    }

    public function test_anlik_stok_defter_toplamina_esittir_ve_ters_kayitla_duzeltilir(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $ledger = app(StockLedger::class);

        $this->seedStock($item, $warehouse, 5_000, 1_000);
        $this->seedStock($item, $warehouse, 2_500, 1_200);

        $waste = $ledger->record([
            'type' => MovementType::Waste,
            'item' => $item->fresh(),
            'warehouse' => $warehouse,
            'qty_milli' => -700,
            'tenant_id' => (int) $item->tenant_id,
            'description' => 'Bozulma',
            'user' => $this->a['user'],
        ]);

        $this->assertSame(6_800, $this->onHandMilli($item, $warehouse));
        $this->assertSame(6_800, $ledger->ledgerBalance($warehouse->id, $item->id));

        // Yanlış fire → SİLİNMEZ; ters kayıtla düzeltilir. Satır sayısı ARTAR.
        $before = StockMovement::withoutTenancy()->count();
        $ledger->reverse($waste, $this->a['user'], 'Hatalı giriş');

        $this->assertSame($before + 1, StockMovement::withoutTenancy()->count());
        $this->assertSame(7_500, $this->onHandMilli($item, $warehouse));
        $this->assertSame(7_500, $ledger->ledgerBalance($warehouse->id, $item->id));
    }

    public function test_toplam_alani_dogrudan_degil_yalniz_defterle_yonetilir(): void
    {
        // Stok kartı güncelleme ucu miktar alanı KABUL ETMEZ: on_hand yalnız
        // defterden türetilir (§17.4 "doğrudan toplam alanı değiştirilmesin").
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 3_000, 100);

        $this->putJson("/api/v1/inventory/items/{$item->id}", [
            'name' => $item->name,
            'base_unit' => $item->base_unit,
            'on_hand' => '999', // yok sayılmalı
            'qty_milli' => 999_000, // yok sayılmalı
        ])->assertOk();

        $this->assertSame(3_000, $this->onHandMilli($item->fresh(), $warehouse));
    }
}
