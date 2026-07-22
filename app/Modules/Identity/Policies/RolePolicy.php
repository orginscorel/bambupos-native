<?php

namespace App\Modules\Identity\Policies;

use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;

class RolePolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('roles.view') || $user->hasPermission('roles.manage');
    }

    public function view(User $user, Role $role): bool
    {
        return $this->sameTenant($user, $role) && $this->viewAny($user);
    }

    public function create(User $user): bool
    {
        return $user->hasPermission('roles.manage');
    }

    public function update(User $user, Role $role): bool
    {
        return $this->sameTenant($user, $role) && $user->hasPermission('roles.manage');
    }

    public function delete(User $user, Role $role): bool
    {
        return $this->sameTenant($user, $role)
            && $user->hasPermission('roles.manage')
            && ! $role->is_system;
    }

    private function sameTenant(User $user, Role $role): bool
    {
        return $user->tenant_id !== null && (int) $user->tenant_id === (int) $role->tenant_id;
    }
}
