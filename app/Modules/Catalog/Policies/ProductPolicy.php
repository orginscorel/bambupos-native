<?php

namespace App\Modules\Catalog\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Catalog\Models\Product;
use App\Modules\Identity\Policies\TenantOwnedPolicy;

class ProductPolicy extends TenantOwnedPolicy
{
    protected string $module = 'catalog';

    public function changePrice(User $user, Product $product): bool
    {
        return $this->ownedByUserTenant($user, $product) && $user->hasPermission('catalog.change_price');
    }
}
