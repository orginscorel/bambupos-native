<?php

namespace App\Modules\Venue\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

/** Kat = masa düzeninin parçası; "tables" izin ailesiyle yönetilir. */
class FloorPolicy extends TenantOwnedPolicy
{
    protected string $module = 'tables';
}
