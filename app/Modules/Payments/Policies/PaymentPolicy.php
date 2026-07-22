<?php

namespace App\Modules\Payments\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Payments\Models\Payment;

/**
 * Ödeme yetkileri (config/authz.php): alma `payments.take`,
 * void/iade AYRI izin `payments.refund`. Kiracı eşitliği her
 * eylemde yeniden doğrulanır (ADR-004 katman 2).
 */
class PaymentPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasPermission('payments.take') || $user->hasPermission('cash.view');
    }

    public function view(User $user, Payment $payment): bool
    {
        return $this->owned($user, $payment) && $this->viewAny($user);
    }

    public function take(User $user): bool
    {
        return $user->hasPermission('payments.take');
    }

    public function query(User $user, Payment $payment): bool
    {
        return $this->owned($user, $payment) && $user->hasPermission('payments.take');
    }

    public function void(User $user, Payment $payment): bool
    {
        return $this->owned($user, $payment) && $user->hasPermission('payments.refund');
    }

    public function refund(User $user, Payment $payment): bool
    {
        return $this->owned($user, $payment) && $user->hasPermission('payments.refund');
    }

    private function owned(User $user, Payment $payment): bool
    {
        return $user->tenant_id !== null && (int) $payment->tenant_id === (int) $user->tenant_id;
    }
}
