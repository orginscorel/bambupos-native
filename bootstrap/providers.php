<?php

use App\Modules\Inventory\InventoryServiceProvider;
use App\Modules\Settings\SettingsServiceProvider;
use App\Modules\Venue\VenueServiceProvider;
use App\Providers\AppServiceProvider;

return [
    AppServiceProvider::class,
    InventoryServiceProvider::class,
    SettingsServiceProvider::class,
    VenueServiceProvider::class,
];
