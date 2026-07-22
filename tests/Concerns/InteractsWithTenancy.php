<?php

namespace Tests\Concerns;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;

/**
 * Test yardımcıları: iki bağımsız kiracı (A/B) + rol/izin kurulumu.
 */
trait InteractsWithTenancy
{
    protected function seedPermissions(): void
    {
        $labels = config('authz.labels', []);

        foreach (config('authz.modules', []) as $module => $actions) {
            foreach ($actions as $action) {
                Permission::query()->firstOrCreate(
                    ['key' => "{$module}.{$action}"],
                    ['module' => $module, 'action' => $action, 'label' => $labels[$action] ?? $action],
                );
            }
        }
    }

    /**
     * @param  array<int, string>  $permissionKeys  boşsa TÜM izinler (sahip gibi)
     * @return array{tenant: Tenant, branch: Branch, user: User, role: Role}
     */
    protected function makeTenantWithUser(array $permissionKeys = []): array
    {
        $tenant = Tenant::factory()->create();
        $branch = Branch::factory()->create(['tenant_id' => $tenant->id]);

        $role = Role::factory()->create(['tenant_id' => $tenant->id]);

        $permissions = $permissionKeys === []
            ? Permission::query()->pluck('id')
            : Permission::query()->whereIn('key', $permissionKeys)->pluck('id');

        $role->permissions()->sync($permissions->all());

        $user = User::factory()->create([
            'tenant_id' => $tenant->id,
            'branch_id' => $branch->id,
        ]);
        $user->roles()->sync([$role->id]);

        return ['tenant' => $tenant, 'branch' => $branch, 'user' => $user, 'role' => $role];
    }

    /** Kiracı bağlamında model üretimi (factory'ler için). */
    protected function asTenant(Tenant $tenant, callable $callback): mixed
    {
        $context = app(TenantContext::class);
        $context->setTenant($tenant);

        try {
            return $callback();
        } finally {
            $context->forget();
        }
    }
}
