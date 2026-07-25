<?php

namespace Tests\Feature\Inventory;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * KİRACI İZOLASYONU (ADR-004): B kiracısı A'nın stok verisini ne görür
 * ne değiştirir — scope fail-closed + policy + scoped binding (404).
 */
class InventoryIsolationTest extends TestCase
{
    use InteractsWithInventory, InteractsWithTenancy, RefreshDatabase;

    public function test_kiracilar_birbirinin_stok_verisini_goremez(): void
    {
        $this->seedPermissions();
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $this->actingAs($a['user']);
        $warehouseA = $this->makeWarehouse($a, ['name' => 'A Ana Depo']);
        $itemA = $this->makeStockItem($a, ['name' => 'A Kıyma']);
        $this->seedStock($itemA, $warehouseA, 1_000, 100);

        // B: listeler BOŞ döner (fail-closed), A kayıtları sızmaz.
        $this->actingAs($b['user']);

        $this->assertSame([], $this->getJson('/api/v1/inventory/items')->assertOk()->json('items'));
        $this->assertSame([], $this->getJson('/api/v1/inventory/warehouses')->assertOk()->json('warehouses'));
        $this->assertSame([], $this->getJson('/api/v1/inventory/movements')->assertOk()->json('movements'));

        // B, A'nın kaydını GÜNCELLEYEMEZ: binding scope 404 üretir.
        $this->putJson("/api/v1/inventory/items/{$itemA->id}", ['name' => 'Çalıntı', 'base_unit' => 'kg'])->assertNotFound();
        $this->putJson("/api/v1/inventory/warehouses/{$warehouseA->id}", ['name' => 'Çalıntı', 'type' => 'main'])->assertNotFound();

        // B, A'nın deposuna hareket YAZAMAZ (exists kuralı kiracıyla süzer → 422).
        $this->postJson('/api/v1/inventory/movements', [
            'warehouse_id' => $warehouseA->id,
            'item_id' => $itemA->id,
            'type' => 'waste',
            'qty' => '1',
            'description' => 'X',
        ])->assertUnprocessable();

        // A'nın stoğu el değmemiş kalır.
        $this->assertSame(1_000, $this->onHandMilli($itemA, $warehouseA));
    }

    public function test_recete_ve_sayim_kiraciya_kapali(): void
    {
        $this->seedPermissions();
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $this->actingAs($a['user']);
        $warehouseA = $this->makeWarehouse($a);
        $itemA = $this->makeStockItem($a);

        $countId = $this->postJson('/api/v1/inventory/counts', ['warehouse_id' => $warehouseA->id])
            ->assertCreated()->json('count.id');

        $this->actingAs($b['user']);
        $this->getJson("/api/v1/inventory/counts/{$countId}")->assertNotFound();
        $this->postJson("/api/v1/inventory/counts/{$countId}/approve")->assertNotFound();

        // B, A'nın stok kalemiyle reçete kuramaz (exists kuralı → 422).
        $this->postJson('/api/v1/inventory/recipes', [
            'item_id' => $itemA->id,
            'lines' => [['item_id' => $itemA->id, 'qty' => '1']],
        ])->assertUnprocessable();
    }
}
