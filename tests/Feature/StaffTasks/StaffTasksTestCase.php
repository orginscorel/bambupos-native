<?php

declare(strict_types=1);

namespace Tests\Feature\StaffTasks;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\StaffTasks\Models\StaffTask;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Personel görevi testleri ortak kurulumu: kiracı/izin tohumu + personel ekleme
 * + görev üretme (portal host yardımcısı dahil).
 */
abstract class StaffTasksTestCase extends TestCase
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

    /**
     * Kiracı bağlamında görev üretir (tenant_id BelongsToTenant ile atanır).
     *
     * @param  array{tenant: Tenant, branch: mixed}  $ctx
     * @param  array<string, mixed>  $attrs
     */
    protected function makeTask(array $ctx, User $assignee, array $attrs = []): StaffTask
    {
        return $this->asTenant($ctx['tenant'], fn (): StaffTask => StaffTask::query()->create(array_merge([
            'branch_id' => $assignee->branch_id,
            'assigned_to_id' => $assignee->id,
            'title' => 'Masaları hazırla',
            'priority' => 'normal',
            'status' => 'open',
            'created_by_id' => $ctx['user']->id,
        ], $attrs)));
    }
}
