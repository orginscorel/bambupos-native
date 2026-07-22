<?php

namespace App\Modules\Ordering\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use App\Modules\Ordering\Models\Order;

class OrderPolicy extends TenantOwnedPolicy
{
    protected string $module = 'orders';

    public function cancel(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $user->hasPermission('orders.cancel');
    }

    public function refund(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $user->hasPermission('orders.refund');
    }

    public function discount(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $user->hasPermission('orders.discount');
    }

    public function comp(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $user->hasPermission('orders.comp');
    }
}
