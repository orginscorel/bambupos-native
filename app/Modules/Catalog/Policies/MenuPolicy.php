<?php

namespace App\Modules\Catalog\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

class MenuPolicy extends TenantOwnedPolicy
{
    protected string $module = 'catalog';
}
