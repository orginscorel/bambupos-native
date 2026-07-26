<?php

namespace Tests\Feature\Notify;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Kds\Models\UserStation;
use App\Modules\Notify\Models\Notification;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * §8 Notify test tabanı: kiracı A (sahip/yönetici) + alıcı kurulum yardımcıları.
 */
abstract class NotifyTestCase extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    /** @var array{tenant: mixed, branch: mixed, user: User, role: mixed} */
    protected array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser(); // sahip: tüm izinler (yönetici)
    }

    /**
     * Kiracı A içinde, verilen izin + (opsiyonel) istasyon atamalı kullanıcı.
     *
     * @param  array<int, string>  $permissionKeys
     * @param  array<int, string>  $stationKeys
     */
    protected function makeUserInA(array $permissionKeys, array $stationKeys = [], ?int $branchId = null): User
    {
        $role = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(
            Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $branchId ?? $this->a['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        foreach ($stationKeys as $key) {
            $this->asTenant($this->a['tenant'], fn () => UserStation::query()->create([
                'user_id' => $user->id,
                'station_key' => $key,
            ]));
        }

        return $user;
    }

    /**
     * Sahip olarak sipariş + kalemler oluşturur (OrderItem::created olayı tetiklenir).
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

    /**
     * @return Collection<int, Notification>
     */
    protected function notificationsFor(int $userId, ?string $type = null): Collection
    {
        return Notification::withoutTenancy()
            ->where('user_id', $userId)
            ->when($type !== null, fn ($q) => $q->where('type', $type))
            ->get();
    }
}
