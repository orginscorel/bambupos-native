<?php

namespace Database\Seeders;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Support\RoleTemplates;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

/**
 * VAR OLAN kiracılarda şablon rollerin varsayılan setlerini senkronlar
 * (idempotent). Kullanıcının açık isteği: "default olarak lazım
 * olabilecekleri açmayı unutma."
 *
 * Kurallar:
 *  - Şablon slug'ıyla eşleşen rol yoksa OLUŞTURULUR.
 *  - Eşleşen rol varsa izin seti şablon varsayılanına GENİŞLETİLİR
 *    (yalnız EKLEME yapılır; işletmenin sonradan AÇTIĞI izinler geri
 *    alınmaz — sahada özelleştirme kaybolmasın).
 *  - Sahip (is_system) daima tüm izinlere tamamlanır.
 */
class StaffRoleDefaultsSeeder extends Seeder
{
    public function run(): void
    {
        $templates = RoleTemplates::all();
        $idsByKey = Permission::query()->pluck('id', 'key');

        app(TenantContext::class)->runWithoutTenancy(function () use ($templates, $idsByKey): void {
            Tenant::query()->each(function (Tenant $tenant) use ($templates, $idsByKey): void {
                foreach ($templates as $slug => $template) {
                    $role = Role::query()
                        ->withoutGlobalScopes()
                        ->where('tenant_id', $tenant->id)
                        ->where('slug', $slug)
                        ->first();

                    if ($role === null) {
                        $role = new Role([
                            'name' => $template['name'],
                            'slug' => $slug,
                            'description' => $template['description'],
                        ]);
                        $role->tenant_id = $tenant->id;
                        $role->is_system = $template['system'];
                        $role->save();
                    }

                    $wanted = $idsByKey->only($template['permissions'])->values()->all();

                    // Yalnız eksikler eklenir; mevcut açık izinler korunur.
                    $role->permissions()->syncWithoutDetaching($wanted);
                }
            });
        });
    }
}
