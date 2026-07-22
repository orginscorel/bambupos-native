<?php

namespace App\Modules\Catalog\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

class CategoryPolicy extends TenantOwnedPolicy
{
    protected string $module = 'catalog';
}
