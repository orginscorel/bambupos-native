<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Models\MovementRequest;
use App\Modules\Inventory\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * YETKİ (config/authz.php): stock.view = okuma, stock.adjust = stok
 * değiştiren her eylem (manuel hareket onayı, sayım onayı, mal kabul…).
 */
class InventoryAuthorizationTest extends TestCase
{
    use InteractsWithInventory, InteractsWithTenancy, RefreshDatabase;

    public function test_stock_view_okur_ama_yazamaz(): void
    {
        $this->seedPermissions();
        $viewer = $this->makeTenantWithUser(['stock.view']);
        $this->actingAs($viewer['user']);

        $this->getJson('/api/v1/inventory/items')->assertOk();
        $this->get('/panel/stok')->assertOk();

        $this->postJson('/api/v1/inventory/items', ['name' => 'X', 'base_unit' => 'kg'])->assertForbidden();
        $this->postJson('/api/v1/inventory/warehouses', ['name' => 'X', 'type' => 'main'])->assertForbidden();
        $this->postJson('/api/v1/inventory/transfers', [])->assertForbidden();
    }

    public function test_izinsiz_kullanici_stok_ekranina_giremez(): void
    {
        $this->seedPermissions();
        $none = $this->makeTenantWithUser(['orders.view']);
        $this->actingAs($none['user']);

        $this->get('/panel/stok')->assertForbidden();
        $this->getJson('/api/v1/inventory/items')->assertForbidden();
        $this->getJson('/api/v1/inventory/movements')->assertForbidden();
    }

    public function test_manuel_hareket_istegi_onay_stock_adjust_ister(): void
    {
        $this->seedPermissions();
        $ctx = $this->makeTenantWithUser(['stock.view']);
        $this->actingAs($ctx['user']);

        $warehouse = $this->makeWarehouse($ctx);
        $item = $this->makeStockItem($ctx);
        $this->seedStock($item, $warehouse, 5_000, 100);

        // stock.view kullanıcısı İSTEK açabilir ama DEFTERE yazılmaz.
        $res = $this->postJson('/api/v1/inventory/movements', [
            'warehouse_id' => $warehouse->id,
            'item_id' => $item->id,
            'type' => 'waste',
            'qty' => '1',
            'description' => 'Bozulan ürün',
        ])->assertCreated();

        $requestId = $res->json('request.id');
        $this->assertNotNull($requestId);
        $this->assertSame(5_000, $this->onHandMilli($item, $warehouse)); // stok DEĞİŞMEDİ

        // Kendisi onaylayamaz (stock.adjust yok).
        $this->postJson("/api/v1/inventory/movement-requests/{$requestId}/approve")->assertForbidden();

        // stock.adjust'lı ikinci kullanıcı (AYNI kiracı) onaylar → defter + seviye.
        $approver = \App\Modules\Identity\Models\User::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ]);
        $role = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->whereIn('key', ['stock.view', 'stock.adjust'])->pluck('id')->all()
        );
        $approver->roles()->sync([$role->id]);

        $this->actingAs($approver)
            ->postJson("/api/v1/inventory/movement-requests/{$requestId}/approve")
            ->assertCreated();

        $this->assertSame(4_000, $this->onHandMilli($item, $warehouse));
        $this->assertSame('approved', MovementRequest::withoutTenancy()->find($requestId)->status);
        $this->assertSame(1, StockMovement::withoutTenancy()->where('ref_type', 'movement_request')->where('ref_id', $requestId)->count());
    }

    public function test_stock_adjust_kullanicisinin_manuel_hareketi_bekletmeden_islenir(): void
    {
        $this->seedPermissions();
        $ctx = $this->makeTenantWithUser(); // tüm izinler
        $this->actingAs($ctx['user']);

        $warehouse = $this->makeWarehouse($ctx);
        $item = $this->makeStockItem($ctx);
        $this->seedStock($item, $warehouse, 5_000, 100);

        $this->postJson('/api/v1/inventory/movements', [
            'warehouse_id' => $warehouse->id,
            'item_id' => $item->id,
            'type' => 'waste',
            'qty' => '0,5',
            'description' => 'Günlük fire',
        ])->assertCreated();

        $this->assertSame(4_500, $this->onHandMilli($item, $warehouse));
    }
}
