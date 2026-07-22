<?php

namespace Tests\Feature\Orders;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Yetki ayrımı (§12.3): indirim / ikram / iptal / iade AYRI izinlerdir.
 * Sipariş açıp servis edebilen garson, izin verilmedikçe bunları yapamaz.
 */
class OrderAuthorizationTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    public function test_garson_izinsiz_indirim_ikram_iptal_iade_yapamaz(): void
    {
        $this->seedPermissions();

        // Sahip (tüm izinler) sipariş hazırlar
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $table = $this->makeTable($owner);
        $product = $this->makeProduct($owner, ['price_minor' => 10000]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $owner['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $itemId = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])
            ->json('order.items.0.id');

        // Dar izinli garson: yalnız görüntüle + oluştur + güncelle
        $waiterRole = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $owner['tenant']->id]);
        $waiterRole->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()
                ->whereIn('key', ['orders.view', 'orders.create', 'orders.update'])
                ->pluck('id')->all(),
        );
        $waiter = \App\Modules\Identity\Models\User::factory()->create([
            'tenant_id' => $owner['tenant']->id,
            'branch_id' => $owner['branch']->id,
        ]);
        $waiter->roles()->sync([$waiterRole->id]);

        $this->actingAs($waiter);

        // Görebilir ve kalem ekleyebilir
        $this->getJson("/api/v1/orders/{$orderId}")->assertOk();
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])->assertCreated();

        // Ama indirim/ikram/iptal/iade 403
        $this->postJson("/api/v1/orders/{$orderId}/discount", ['type' => 'percent', 'value' => 5, 'reason' => 'x y z'])->assertForbidden();
        $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/comp", ['reason' => 'ikram deneme'])->assertForbidden();
        $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/cancel", ['reason' => 'iptal deneme'])->assertForbidden();
        $this->postJson("/api/v1/orders/{$orderId}/cancel", ['reason' => 'iptal deneme'])->assertForbidden();
        $this->postJson("/api/v1/orders/{$orderId}/refund", ['reason' => 'iade deneme'])->assertForbidden();
    }

    public function test_gorutuleme_izni_olmayan_panel_sayfasina_giremez(): void
    {
        $this->seedPermissions();

        $ctx = $this->makeTenantWithUser(['catalog.view']); // sipariş izni YOK
        $this->actingAs($ctx['user']);

        $this->getJson('/api/v1/orders')->assertForbidden();
        $this->getJson('/api/v1/orders/board')->assertForbidden();
        $this->get('/panel/siparisler')->assertForbidden();
    }
}
