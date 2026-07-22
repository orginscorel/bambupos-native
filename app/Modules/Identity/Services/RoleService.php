<?php

namespace App\Modules\Identity\Services;

use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Rol yönetimi (katman 4: servis). Kurallar:
 *  - Roller daima bağlamdaki kiracıda oluşur (BelongsToTenant creating).
 *  - Yetki yükseltme engeli: bir kullanıcı, rolüne KENDİSİNDE OLMAYAN
 *    bir izni ekleyemez.
 *  - is_system roller silinemez / izin seti değiştirilemez.
 */
class RoleService
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /**
     * @param  array<int, int>  $permissionIds
     */
    public function create(User $actor, string $name, ?string $description, array $permissionIds): Role
    {
        $permissions = $this->resolveGrantablePermissions($actor, $permissionIds);

        $role = Role::create([
            'name' => $name,
            'slug' => Str::slug($name).'-'.Str::lower(Str::random(4)),
            'description' => $description,
        ]);

        $role->permissions()->sync($permissions->pluck('id')->all());

        $this->audit->log('roles.permissions_set', $role, null, ['permissions' => $permissions->pluck('key')->all()]);

        return $role;
    }

    /**
     * @param  array<int, int>|null  $permissionIds
     */
    public function update(User $actor, Role $role, array $attributes, ?array $permissionIds): Role
    {
        if ($role->is_system) {
            throw ValidationException::withMessages([
                'role' => ['Sistem rolleri düzenlenemez.'],
            ])->status(403);
        }

        $role->fill($attributes)->save();

        if ($permissionIds !== null) {
            $permissions = $this->resolveGrantablePermissions($actor, $permissionIds);

            $old = $role->permissions()->pluck('key')->all();
            $role->permissions()->sync($permissions->pluck('id')->all());

            $this->audit->log('roles.permissions_set', $role, ['permissions' => $old], ['permissions' => $permissions->pluck('key')->all()]);
        }

        return $role;
    }

    /**
     * Rol kopyalama: ad + izin seti klonlanır (is_system taşınmaz).
     * Yetki yükseltme engeli kopyada da geçerlidir: kaynak rolde aktörün
     * sahip olmadığı izin varsa kopyalanamaz.
     */
    public function copy(User $actor, Role $source, ?string $name = null): Role
    {
        $permissionIds = $source->permissions()->pluck('permissions.id')->all();

        return $this->create(
            $actor,
            $name ?: ($source->name.' (Kopya)'),
            $source->description,
            $permissionIds,
        );
    }

    public function delete(Role $role): void
    {
        if ($role->is_system) {
            throw ValidationException::withMessages([
                'role' => ['Sistem rolleri silinemez.'],
            ])->status(403);
        }

        $role->users()->detach();
        $role->permissions()->detach();
        $role->delete();
    }

    /**
     * Yetki yükseltme engeli: istekteki izin id'leri katalogdan doğrulanır
     * ve aktörün sahip olmadığı her izin reddedilir.
     *
     * @param  array<int, int>  $permissionIds
     * @return \Illuminate\Support\Collection<int, Permission>
     */
    private function resolveGrantablePermissions(User $actor, array $permissionIds): \Illuminate\Support\Collection
    {
        $permissions = Permission::query()->whereIn('id', $permissionIds)->get();

        $actorKeys = $actor->permissionKeys();

        $forbidden = $permissions->reject(fn (Permission $p) => in_array($p->key, $actorKeys, true));

        if ($forbidden->isNotEmpty()) {
            throw ValidationException::withMessages([
                'permissions' => [
                    'Sahip olmadığınız izinleri bir role ekleyemezsiniz: '.$forbidden->pluck('key')->implode(', '),
                ],
            ])->status(403);
        }

        return $permissions;
    }
}
