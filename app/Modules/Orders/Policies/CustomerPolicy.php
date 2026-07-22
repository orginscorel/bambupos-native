<?php

namespace App\Modules\Orders\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

/** Faz-1 iskeletinden taşındı (Ordering → Orders). */
class CustomerPolicy extends TenantOwnedPolicy
{
    protected string $module = 'customers';
}
