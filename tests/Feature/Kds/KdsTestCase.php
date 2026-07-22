<?php

namespace Tests\Feature\Kds;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * KDS test tabanı: kiracı A (sahip) + sipariş kurulum yardımcıları.
 */
abstract class KdsTestCase extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    /** @var array{tenant: mixed, branch: mixed, user: User, role: mixed} */
    protected array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser(); // sahip: tüm izinler
    }

    /** Kiracı A içinde, verilen izinlerle İKİNCİ bir kullanıcı. */
    protected function makeUserInA(array $permissionKeys): User
    {
        $role = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(
            Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    /**
     * Sahip olarak sipariş + kalemler oluşturur.
     *
     * @param  array<int, array{station?: string|null, name?: string, qty?: int}>  $items
     * @return array{order_id: int, item_ids: array<int, int>, version: int}
     */
    protected function createOrderWithItems(array $items): array
    {
        $this->actingAs($this->a['user']);

        $table = $this->makeTable($this->a);

        $orderId = (int) $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $itemIds = [];

        foreach ($items as $spec) {
            $product = $this->makeProduct($this->a, [
                'name' => $spec['name'] ?? 'Ürün',
                'station' => $spec['station'] ?? null,
                'price_minor' => 10000,
            ]);

            $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
                'product_id' => $product->id,
                'qty' => $spec['qty'] ?? 1,
            ])->assertCreated();

            $itemIds[] = (int) collect($res->json('order.items'))->last()['id'];
        }

        $version = (int) $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');

        auth('web')->logout();

        return ['order_id' => $orderId, 'item_ids' => $itemIds, 'version' => $version];
    }
}
