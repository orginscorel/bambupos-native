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

            // ŞUBE KAPSAMI: iki-şube senaryosunu (izolasyon + değiştirici)
            // elle test edebilmek için ikinci demo şube.
            $branch2 = new Branch([
                'name' => 'İkinci Şube',
                'code' => 'SUBE2',
                'is_active' => true,
            ]);
            $branch2->tenant_id = $tenant->id;
            $branch2->save();

            // Rol setleri TEK KAYNAKTAN: config/authz.php 'templates'
            // (Personel-Yetki — "default olarak lazım olabilecekler" açık).
            $allPermissionIds = Permission::query()->pluck('id', 'key');

            $ownerRole = null;

            foreach (\App\Modules\Identity\Support\RoleTemplates::all() as $slug => $template) {
                $role = new Role([
                    'name' => $template['name'],
                    'slug' => $slug,
                    'description' => $template['description'],
                ]);
                $role->tenant_id = $tenant->id;
                $role->is_system = $template['system'];
                $role->save();

                $role->permissions()->sync(
                    $allPermissionIds->only($template['permissions'])->values()->all()
                );

                if ($slug === 'sahip') {
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
