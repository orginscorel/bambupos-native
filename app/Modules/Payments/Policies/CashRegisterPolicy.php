<?php

namespace App\Modules\Payments\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Payments\Models\CashRegister;

/**
 * Kasa yetkileri: görüntüleme `cash.view`; açılış/kapanış/sayım/hareket
 * `cash.close` ("kasa yönet" — izin kataloğundaki mevcut anahtar).
 */
class CashRegisterPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('cash.view');
    }

    public function view(User $user, CashRegister $register): bool
    {
        return $this->owned($user, $register) && $user->hasPermission('cash.view');
    }

    public function manage(User $user, ?CashRegister $register = null): bool
    {
        return ($register === null || $this->owned($user, $register)) && $user->hasPermission('cash.close');
    }

    /** ŞUBE KAPSAMI: kasa YALNIZ geçerli şubede görüntülenip yönetilebilir. */
    private function owned(User $user, CashRegister $register): bool
    {
        if ($user->tenant_id === null || (int) $register->tenant_id !== (int) $user->tenant_id) {
            return false;
        }

        $branchId = $register->getAttribute('branch_id');

        return $branchId === null
            || (int) $branchId === (int) app(\App\Modules\Tenancy\BranchContext::class)->currentBranchId();
    }
}
