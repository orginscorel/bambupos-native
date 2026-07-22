<?php

namespace App\Modules\Ordering\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

class CustomerPolicy extends TenantOwnedPolicy
{
    protected string $module = 'customers';
}
