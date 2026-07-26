<?php

namespace Tests\Feature\Portal;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Personel Portalı test tabanı: portal host yardımcıları + personel kurulumu.
 */
abstract class PortalTestCase extends TestCase
{
    use InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    /** Portal host'undaki tam URL (Route::domain eşleşmesi için). */
    protected function portalUrl(string $path = '/'): string
    {
        return 'http://'.config('portal.host').$path;
    }

    /** Panel (normal) host'undaki tam URL — portal host DEĞİL. */
    protected function panelUrl(string $path = '/'): string
    {
        return 'http://qrmenu.example.test'.$path;
    }

    /**
     * Kiracıya izinli personel ekler.
     *
     * @param  array{tenant: Tenant, branch: mixed}  $ctx
     * @param  array<int, string>  $permissionKeys
     */
    protected function addStaff(array $ctx, array $permissionKeys = ['catalog.view'], ?int $branchId = null): User
    {
        $role = Role::factory()->create(['tenant_id' => $ctx['tenant']->id]);
        $role->permissions()->sync(
            Permission::query()->whereIn('key', $permissionKeys)->pluck('id')->all(),
        );

        $user = User::factory()->create([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $branchId ?? $ctx['branch']->id,
        ]);
        $user->roles()->sync([$role->id]);

        return $user;
    }

    /** Kullanıcıyı "mesaide" yapar: açık time_entry oluşturur. */
    protected function openShift(Tenant $tenant, User $user, ?int $branchId = null): TimeEntry
    {
        return $this->asTenant($tenant, fn () => TimeEntry::query()->create([
            'branch_id' => $branchId ?? $user->branch_id,
            'user_id' => $user->id,
            'clock_in_at' => now(),
            'method_in' => 'portal',
            'status' => TimeEntry::STATUS_OPEN,
        ]));
    }
}
