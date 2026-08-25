<?php

use App\Modules\Commission\Http\Controllers\CommissionController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Prim / Komisyon (feature: commission)
|--------------------------------------------------------------------------
| Özellik kapalıysa `feature:commission` tüm grubu 404 yapar. Yetki:
| commission.view (rapor) / commission.manage (şema yazma) — controller'da.
*/
Route::middleware(['web', 'auth:web', 'tenant', 'feature:commission'])->group(function (): void {

    Route::get('/panel/prim', fn () => Inertia::render('Panel/Commission/Index'))->name('panel.commission.index');

    Route::prefix('api/v1/commission')->group(function (): void {
        Route::get('schemes', [CommissionController::class, 'index'])->name('commission.schemes.index');
        Route::post('schemes', [CommissionController::class, 'store'])->name('commission.schemes.store');
        Route::put('schemes/{scheme}', [CommissionController::class, 'update'])->whereNumber('scheme')->name('commission.schemes.update');
        Route::delete('schemes/{scheme}', [CommissionController::class, 'destroy'])->whereNumber('scheme')->name('commission.schemes.destroy');
        Route::get('report', [CommissionController::class, 'report'])->name('commission.report');
    });
});
