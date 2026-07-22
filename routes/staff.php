<?php

use App\Modules\Identity\Http\Controllers\RoleController;
use App\Modules\Identity\Http\Controllers\StaffAccessController;
use App\Modules\Identity\Http\Controllers\StaffPageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Personel-Yetki ajanı: personel + rol/yetki ekranları.
| Temel personel/rol CRUD'u routes/identity.php'de (apiResource);
| burada panel sayfaları ve ek uçlar (istisna, PIN, işten çıkarma, kopya).
| Tüm uçlar oturum + kiracı bağlamı ister; policy'ler izinleri denetler.
|--------------------------------------------------------------------------
*/

Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    /* ---- Panel ekranları (Inertia) ---- */
    Route::prefix('panel/personel')->group(function (): void {
        Route::get('/', [StaffPageController::class, 'index'])->name('panel.staff.index');
        Route::get('/roller', [StaffPageController::class, 'roles'])->name('panel.staff.roles');
    });

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/staff-access')->group(function (): void {
        Route::get('meta', [StaffAccessController::class, 'meta'])->name('staff-access.meta');

        Route::get('{staff}/effective', [StaffAccessController::class, 'effective'])->name('staff-access.effective');
        Route::put('{staff}/overrides', [StaffAccessController::class, 'setOverrides'])->name('staff-access.overrides');
        Route::post('{staff}/pin', [StaffAccessController::class, 'setPin'])->name('staff-access.pin.set');
        Route::delete('{staff}/pin', [StaffAccessController::class, 'clearPin'])->name('staff-access.pin.clear');
        Route::post('{staff}/send-reset-link', [StaffAccessController::class, 'sendResetLink'])->name('staff-access.reset-link');
        Route::post('{staff}/terminate', [StaffAccessController::class, 'terminate'])->name('staff-access.terminate');
        Route::post('{staff}/activate', [StaffAccessController::class, 'activate'])->name('staff-access.activate');
    });

    Route::post('api/v1/roles/{role}/copy', [RoleController::class, 'copy'])->name('roles.copy');
});
