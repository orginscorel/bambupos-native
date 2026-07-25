<?php

namespace Tests\Feature\Shifts;

use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Shifts testleri ortak kurulumu: kiracı + yönetici (tüm izinler) +
 * sınırlı personel (yalnız catalog.view) yardımcıları.
 */
abstract class ShiftsTestCase extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /**
     * Aynı kiracıya İKİNCİ (sınırlı yetkili) personel ekler.
     *
     * @param  array{tenant: Tenant, branch: mixed}  $ctx
     * @param  array<int, string>  $permissionKeys
     */
    protected function addStaff(array $ctx, array $permissionKeys = ['catalog.view'], array $attrs = []): User
    {
        $role = Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create(array_merge([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ], $attrs));
        $user->roles()->sync([$role->id]);

        return $user;
    }

    /** PIN atar (bcrypt; PinService kuralına uygun 6 haneli). */
    protected function setPin(User $user, string $pin): void
    {
        $user->forceFill(['pin_hash' => Hash::make($pin)])->save();
    }

    /**
     * @param  array{tenant: Tenant, branch: mixed}  $ctx
     */
    protected function makeShift(array $ctx, User $user, string $start, string $end, array $attrs = []): Shift
    {
        return $this->asTenant($ctx['tenant'], function () use ($ctx, $user, $start, $end, $attrs): Shift {
            return Shift::query()->create(array_merge([
                'branch_id' => $ctx['branch']->id,
                'user_id' => $user->id,
                'starts_at' => $start,
                'ends_at' => $end,
                'break_min' => 0,
            ], $attrs));
        });
    }
}
