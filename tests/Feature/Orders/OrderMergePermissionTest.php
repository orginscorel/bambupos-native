<?php

namespace Tests\Feature\Orders;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Masa/adisyon birleştirme AYRI izindir (orders.merge_tables): yalnız
 * Garson (+ yönetim). orders.update olsa bile merge_tables yoksa 403.
 */
class OrderMergePermissionTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    /** Aynı kiracıda verilen izinlerle personel kullanıcısı üretir. */
    private function makeStaff(array $ctx, array $permissionKeys): User
    {
        $role = Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    /** İki açık adisyon kurar; ikinci adisyonun id'sini döndürür. */
    private function twoOpenOrders(array $ctx): array
    {
        $product = $this->makeProduct($ctx, ['price_minor' => 5000]);

        $o1 = $this->postJson('/api/v1/orders', [
            'branch_id' => $ctx['branch']->id, 'channel' => 'table', 'table_id' => $this->makeTable($ctx)->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$o1}/items", ['product_id' => $product->id, 'qty' => 1]);

        $o2 = $this->postJson('/api/v1/orders', [
            'branch_id' => $ctx['branch']->id, 'channel' => 'table', 'table_id' => $this->makeTable($ctx)->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$o2}/items", ['product_id' => $product->id, 'qty' => 1]);

        return [$o1, $o2];
    }

    public function test_garson_merge_tables_izniyle_birlestirebilir(): void
    {
        $this->seedPermissions();
        $owner = $this->makeTenantWithUser();

        $this->actingAs($owner['user']);
        [$o1, $o2] = $this->twoOpenOrders($owner);

        // Varsayılan garson izinleri (config/authz.php garson şablonu).
        $garson = $this->makeStaff($owner, [
            'orders.view', 'orders.create', 'orders.update', 'orders.merge_tables', 'tables.view',
        ]);
        $this->actingAs($garson);

        $res = $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertOk();
        $this->assertSame(10000, $res->json('order.total_minor'));
        $this->assertSame('cancelled', $this->getJson("/api/v1/orders/{$o2}")->json('order.status'));
    }

    public function test_merge_tables_izni_olmayan_orders_update_olsa_bile_birlestiremez(): void
    {
        $this->seedPermissions();
        $owner = $this->makeTenantWithUser();

        $this->actingAs($owner['user']);
        [$o1, $o2] = $this->twoOpenOrders($owner);

        // orders.update VAR ama orders.merge_tables YOK → 403.
        $noMerge = $this->makeStaff($owner, [
            'orders.view', 'orders.create', 'orders.update', 'tables.view',
        ]);
        $this->actingAs($noMerge);

        $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertForbidden();

        // Adisyonlar dokunulmadan açık kalır.
        $this->assertTrue($this->getJson("/api/v1/orders/{$o2}")->json('order.is_open'));
    }

    public function test_mutfak_birlestiremez(): void
    {
        $this->seedPermissions();
        $owner = $this->makeTenantWithUser();

        $this->actingAs($owner['user']);
        [$o1, $o2] = $this->twoOpenOrders($owner);

        // Mutfak varsayılanı yalnız kds.view (sipariş/merge izni YOK).
        $mutfak = $this->makeStaff($owner, ['kds.view']);
        $this->actingAs($mutfak);

        $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertForbidden();
    }
}
