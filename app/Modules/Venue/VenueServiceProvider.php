<?php

namespace App\Modules\Venue;

use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\Area;
use App\Modules\Venue\Models\Floor;
use App\Modules\Venue\Policies\AreaPolicy;
use App\Modules\Venue\Policies\BranchPolicy;
use App\Modules\Venue\Policies\FloorPolicy;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

/**
 * Venue modülü kayıtları (ADR-002: modül kendi sınırının içinde kalır;
 * AppServiceProvider'a dokunmadan kendi policy'lerini bağlar).
 */
class VenueServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        Gate::policy(Branch::class, BranchPolicy::class);
        Gate::policy(Floor::class, FloorPolicy::class);
        Gate::policy(Area::class, AreaPolicy::class);
    }
}
