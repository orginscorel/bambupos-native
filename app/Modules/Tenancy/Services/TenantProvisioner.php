<?php

namespace App\Modules\Tenancy\Services;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\RoleTemplates;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Yeni işletme (tenant) provisioning — süper-adminden "Yeni POS mağazası aç".
 * DemoTenantSeeder ile aynı yapı: Tenant + Merkez Şube + config/authz roller
 * + sahip kullanıcı. Tek transaction; tenant-scope BYPASS (runWithoutTenancy).
 *
 * DÖNÜŞ: ['tenant' => Tenant, 'owner' => User, 'password' => string].
 * Parola YALNIZCA bir kez geri döner (kurulum ekranında gösterilir); saklanmaz.
 */
class TenantProvisioner
{
    public function __construct(private readonly TenantContext $context)
    {
    }

    /**
     * @param  array{name:string, slug?:?string, owner_name?:?string, owner_email:string, plan?:?string, trial_days?:?int, owner_password?:?string}  $data
     * @return array{tenant: Tenant, owner: User, password: string}
     */
    public function provision(array $data): array
    {
        return $this->context->runWithoutTenancy(fn () => DB::transaction(function () use ($data) {
            $plan = $data['plan'] ?? 'trial';
            $trialDays = (int) ($data['trial_days'] ?? 14);

            $tenant = Tenant::query()->create([
                'name' => trim($data['name']),
                'slug' => $this->uniqueSlug($data['slug'] ?? $data['name']),
                'status' => Tenant::STATUS_ACTIVE,
                'plan' => $plan,
                'trial_ends_at' => $plan === 'trial' ? now()->addDays($trialDays)->toDateString() : null,
            ]);

            // Varsayılan merkez şube.
            $branch = new Branch(['name' => 'Merkez Şube', 'code' => 'MERKEZ', 'is_active' => true]);
            $branch->tenant_id = $tenant->id;
            $branch->save();

            // Roller — config/authz.php şablonlarından (tek kaynak).
            $allPermissionIds = Permission::query()->pluck('id', 'key');
            $ownerRole = null;

            foreach (RoleTemplates::all() as $slug => $template) {
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

            // Sahip (patron) kullanıcısı.
            $password = ($data['owner_password'] ?? null) ?: Str::password(14);
            [$firstName, $lastName] = $this->splitName($data['owner_name'] ?? 'İşletme Sahibi');

            $owner = new User([
                'first_name' => $firstName,
                'last_name' => $lastName,
                'email' => strtolower(trim($data['owner_email'])),
                'staff_code' => 'SAHIP',
                'position' => 'İşletme Sahibi',
                'locale' => 'tr',
            ]);
            $owner->tenant_id = $tenant->id;
            $owner->branch_id = $branch->id;
            $owner->password = Hash::make($password);
            $owner->is_active = true;
            $owner->email_verified_at = now();
            $owner->save();

            if ($ownerRole !== null) {
                $owner->roles()->sync([$ownerRole->id]);
            }

            return ['tenant' => $tenant, 'owner' => $owner, 'password' => $password];
        }));
    }

    /** Slug'ı benzersizleştir (çakışırsa -2, -3 … ekler). */
    private function uniqueSlug(string $base): string
    {
        $slug = Str::slug($base) ?: 'isletme';
        $candidate = $slug;
        $i = 1;
        while (Tenant::query()->where('slug', $candidate)->exists()) {
            $candidate = $slug . '-' . (++$i);
        }
        return $candidate;
    }

    /** "Ahmet Yılmaz" → ['Ahmet', 'Yılmaz']; tek kelime → soyad boş. */
    private function splitName(string $full): array
    {
        $full = trim(preg_replace('/\s+/', ' ', $full)) ?: 'İşletme Sahibi';
        $parts = explode(' ', $full);
        $last = count($parts) > 1 ? array_pop($parts) : '';
        return [implode(' ', $parts), $last];
    }
}
