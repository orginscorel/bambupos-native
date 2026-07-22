<?php

namespace App\Modules\Identity\Policies;

use App\Modules\Identity\Models\User;

/**
 * Personel policy'si: staff.view / staff.manage + kiracı eşitliği.
 */
class StaffPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('staff.view');
    }

    public function view(User $user, User $staff): bool
    {
        return $this->sameTenant($user, $staff)
            && ($user->is($staff) || $user->hasPermission('staff.view'));
    }

    public function create(User $user): bool
    {
        return $user->hasPermission('staff.manage');
    }

    public function update(User $user, User $staff): bool
    {
        return $this->sameTenant($user, $staff) && $user->hasPermission('staff.manage');
    }

    public function delete(User $user, User $staff): bool
    {
        return $this->sameTenant($user, $staff)
            && $user->hasPermission('staff.manage')
            && ! $user->is($staff); // kendi hesabını silemez
    }

    private function sameTenant(User $user, User $staff): bool
    {
        return $user->tenant_id !== null && (int) $user->tenant_id === (int) $staff->tenant_id;
    }
}
