<?php

namespace App\Modules\Payments\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Payments\Models\CashSession;

/** Kasa oturumu yetkileri (bkz. CashRegisterPolicy). */
class CashSessionPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('cash.view');
    }

    public function view(User $user, CashSession $session): bool
    {
        return $this->owned($user, $session) && $user->hasPermission('cash.view');
    }

    public function manage(User $user, CashSession $session): bool
    {
        return $this->owned($user, $session) && $user->hasPermission('cash.close');
    }

    /** ŞUBE KAPSAMI: kasa oturumu YALNIZ geçerli şubede görüntülenip yönetilebilir. */
    private function owned(User $user, CashSession $session): bool
    {
        if ($user->tenant_id === null || (int) $session->tenant_id !== (int) $user->tenant_id) {
            return false;
        }

        $branchId = $session->getAttribute('branch_id');

        return $branchId === null
            || (int) $branchId === (int) app(\App\Modules\Tenancy\BranchContext::class)->currentBranchId();
    }
}
