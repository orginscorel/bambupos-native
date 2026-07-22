<?php

use App\Modules\Venue\VenueServiceProvider;
use App\Providers\AppServiceProvider;

return [
    AppServiceProvider::class,
    VenueServiceProvider::class,
    \App\Modules\Settings\SettingsServiceProvider::class,
];
