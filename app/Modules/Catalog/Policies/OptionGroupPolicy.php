<?php

namespace App\Modules\Catalog\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

class OptionGroupPolicy extends TenantOwnedPolicy
{
    protected string $module = 'catalog';
}
