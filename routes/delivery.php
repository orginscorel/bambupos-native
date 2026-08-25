<?php

use App\Modules\Delivery\Http\Controllers\DeliveryController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Teslimat / Paket-Kurye (feature: delivery)
|--------------------------------------------------------------------------
| Özellik kapalıysa `feature:delivery` middleware'i tüm grubu 404 yapar
| ("kapalı = yok"). Yetki: delivery.view (pano) / delivery.manage (yazma) —
| controller içinde denetlenir.
*/
Route::middleware(['web', 'auth:web', 'tenant', 'feature:delivery'])->group(function (): void {

    Route::get('/panel/teslimat', fn () => Inertia::render('Panel/Delivery/Board'))->name('panel.delivery.index');

    Route::prefix('api/v1/deliveries')->group(function (): void {
        Route::get('/', [DeliveryController::class, 'index'])->name('deliveries.index');
        Route::post('{order}/assign', [DeliveryController::class, 'assign'])->whereNumber('order')->name('deliveries.assign');
        Route::post('{order}/status', [DeliveryController::class, 'status'])->whereNumber('order')->name('deliveries.status');
    });
});
