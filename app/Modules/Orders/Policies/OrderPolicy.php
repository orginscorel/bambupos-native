<?php

namespace App\Modules\Orders\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use App\Modules\Orders\Models\Order;

/**
 * İkram/indirim/iptal/iade AYRI izinlerdir (config/authz.php: orders.*).
 * Kiracı eşitliği her eylemde yeniden doğrulanır (ADR-004 katman 2).
 */
class OrderPolicy extends TenantOwnedPolicy
{
    protected string $module = 'orders';

    /**
     * ŞUBE KAPSAMI: adisyon görüntüleme/mutasyon YALNIZ geçerli şubede.
     * view+update (addItem/pay/setStatus/... hepsi update'ten geçer) burada
     * şubeyle sınırlanınca tüm adisyon işlemleri çapraz-şubeye kapanır.
     */
    public function view(User $user, \Illuminate\Database\Eloquent\Model $order): bool
    {
        return parent::view($user, $order) && $this->inCurrentBranch($order);
    }

    public function update(User $user, \Illuminate\Database\Eloquent\Model $order): bool
    {
        return parent::update($user, $order) && $this->inCurrentBranch($order);
    }

    public function cancel(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $this->inCurrentBranch($order)
            && $user->hasPermission('orders.cancel');
    }

    public function refund(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $this->inCurrentBranch($order)
            && $user->hasPermission('orders.refund');
    }

    public function discount(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $this->inCurrentBranch($order)
            && $user->hasPermission('orders.discount');
    }

    public function comp(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $this->inCurrentBranch($order)
            && $user->hasPermission('orders.comp');
    }

    /**
     * Masa/adisyon birleştirme AYRI izindir (orders.merge_tables): yalnız
     * Garson (+ yönetim). Mutfak/Barista/Komi/Kasiyer birleştiremez.
     */
    public function mergeTables(User $user, Order $order): bool
    {
        return $this->ownedByUserTenant($user, $order) && $this->inCurrentBranch($order)
            && $user->hasPermission('orders.merge_tables');
    }
}
