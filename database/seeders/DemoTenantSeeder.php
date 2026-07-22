<?php

namespace Database\Seeders;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Demo kiracı + şube + roller + sahip kullanıcısı (idempotent).
 * Sahip parolası .env SEED_OWNER_PASSWORD'dan okunur; yoksa rastgele
 * üretilir ve HİÇBİR yere (log/rapor/çıktı) yazılmaz — "Parolamı unuttum"
 * akışıyla belirlenebilir.
 */
class DemoTenantSeeder extends Seeder
{
    public function run(): void
    {
        if (Tenant::query()->where('slug', 'demo')->exists()) {
            return;
        }

        app(TenantContext::class)->runWithoutTenancy(function (): void {
            $tenant = Tenant::query()->create([
                'name' => 'Demo İşletme',
                'slug' => 'demo',
                'status' => 'active',
            ]);

            $branch = new Branch([
                'name' => 'Merkez Şube',
                'code' => 'MERKEZ',
                'is_active' => true,
            ]);
            $branch->tenant_id = $tenant->id;
            $branch->save();

            $allPermissionIds = Permission::query()->pluck('id', 'key');

            $roles = [
                'Sahip' => ['system' => true, 'perms' => $allPermissionIds->values()->all()],
                'Müdür' => ['system' => false, 'perms' => $allPermissionIds->except(['integrations.manage'])->values()->all()],
                'Garson' => ['system' => false, 'perms' => $allPermissionIds->only([
                    'catalog.view', 'orders.view', 'orders.create', 'orders.update', 'tables.view', 'customers.view',
                ])->values()->all()],
                'Kasiyer' => ['system' => false, 'perms' => $allPermissionIds->only([
                    'orders.view', 'payments.take', 'cash.view', 'cash.close',
                ])->values()->all()],
                // KDS (Faz-4): mutfak yalnız operasyon görür — fiyat/ciro izni YOK.
                'Mutfak' => ['system' => false, 'perms' => $allPermissionIds->only([
                    'kds.view',
                ])->values()->all()],
                'Komi' => ['system' => false, 'perms' => $allPermissionIds->only([
                    'kds.deliver',
                ])->values()->all()],
            ];

            $ownerRole = null;

            foreach ($roles as $name => $definition) {
                $role = new Role([
                    'name' => $name,
                    'slug' => Str::slug($name),
                    'description' => $name.' rolü',
                ]);
                $role->tenant_id = $tenant->id;
                $role->is_system = $definition['system'];
                $role->save();

                $role->permissions()->sync($definition['perms']);

                if ($name === 'Sahip') {
                    $ownerRole = $role;
                }
            }

            $password = config('authz.seed_owner_password') ?: Str::password(24);

            $owner = new User([
                'first_name' => 'Demo',
                'last_name' => 'Sahip',
                'email' => 'sahip@demo.qrmenu.local',
                'staff_code' => 'SAHIP01',
                'position' => 'İşletme Sahibi',
                'locale' => 'tr',
            ]);
            $owner->tenant_id = $tenant->id;
            $owner->branch_id = $branch->id;
            $owner->password = Hash::make($password);
            $owner->is_active = true;
            $owner->email_verified_at = now();
            $owner->save();

            $owner->roles()->sync([$ownerRole->id]);
        });
    }
}
