<?php

namespace App\Modules\Tables\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

class TablePolicy extends TenantOwnedPolicy
{
    protected string $module = 'tables';
}
