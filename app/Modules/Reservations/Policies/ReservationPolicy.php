<?php

namespace App\Modules\Reservations\Policies;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Policies\TenantOwnedPolicy;
use Illuminate\Database\Eloquent\Model;

class ReservationPolicy extends TenantOwnedPolicy
{
    protected string $module = 'reservations';

    /** Durum geçişleri / onay / kapora: manage izni. */
    public function manage(User $user, Model $model): bool
    {
        return $this->ownedByUserTenant($user, $model) && $user->hasPermission('reservations.manage');
    }

    /** Alerji notu gibi hassas alanlar. */
    public function viewSensitive(User $user): bool
    {
        return $user->hasPermission('reservations.view_sensitive');
    }
}
