<?php

namespace App\Modules\Venue\Policies;

use App\Modules\Identity\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * Şube yetkileri. İzin kataloğunda şube için yalnız view/manage vardır;
 * bu yüzden TenantOwnedPolicy'nin create/update/delete anahtarları yerine
 * "branches.manage" denetlenir (katman 2: tenant eşitliği yeniden doğrulanır).
 */
class BranchPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('branches.view');
    }

    public function view(User $user, Model $model): bool
    {
        return $this->owned($user, $model) && $user->hasPermission('branches.view');
    }

    public function create(User $user): bool
    {
        return $user->hasPermission('branches.manage');
    }

    public function update(User $user, Model $model): bool
    {
        return $this->owned($user, $model) && $user->hasPermission('branches.manage');
    }

    public function delete(User $user, Model $model): bool
    {
        return $this->owned($user, $model) && $user->hasPermission('branches.manage');
    }

    private function owned(User $user, Model $model): bool
    {
        return $user->tenant_id !== null
            && (int) $model->getAttribute('tenant_id') === (int) $user->tenant_id;
    }
}
