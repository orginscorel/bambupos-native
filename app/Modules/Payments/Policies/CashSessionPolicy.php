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

    private function owned(User $user, CashSession $session): bool
    {
        return $user->tenant_id !== null && (int) $session->tenant_id === (int) $user->tenant_id;
    }
}
