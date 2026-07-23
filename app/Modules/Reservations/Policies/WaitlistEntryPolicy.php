<?php

namespace App\Modules\Reservations\Policies;

use App\Modules\Identity\Policies\TenantOwnedPolicy;

/** Bekleme listesi, rezervasyon izin setini paylaşır (ayrı katalog şişirmez). */
class WaitlistEntryPolicy extends TenantOwnedPolicy
{
    protected string $module = 'reservations';
}
