<?php

namespace App\Modules\Venue\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

/** Salon/alan = masa düzeninin parçası; "tables" izin ailesiyle yönetilir. */
class AreaPolicy extends TenantOwnedPolicy
{
    protected string $module = 'tables';
}
