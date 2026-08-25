<?php

use App\Modules\Identity\Http\Controllers\ImpersonationController;
use App\Modules\Identity\Http\Controllers\RoleController;
use App\Modules\Identity\Http\Controllers\StaffAccessController;
use App\Modules\Identity\Http\Controllers\StaffPageController;
use App\Modules\StaffTasks\Http\Controllers\StaffTaskAdminController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

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

    // Görev atama panosu (yönetici). Sayfa ince; yetkiyi API (tasks.view/assign)
    // ve navigasyon süzgeci (permission: tasks.view) uygular.
    Route::get('/panel/gorevler', fn () => Inertia::render('Panel/Staff/StaffTasks'))->name('panel.tasks.index');

    /* ---- Görev (staff_tasks) yönetici uçları ---- */
    Route::prefix('api/v1/tasks')->group(function (): void {
        Route::get('/', [StaffTaskAdminController::class, 'index'])->name('tasks.index');
        Route::post('/', [StaffTaskAdminController::class, 'store'])->name('tasks.store');
        Route::put('{task}', [StaffTaskAdminController::class, 'update'])->name('tasks.update');
        Route::delete('{task}', [StaffTaskAdminController::class, 'destroy'])->name('tasks.destroy');
    });

    /* ---- JSON uçları ---- */
    Route::prefix('api/v1/staff-access')->group(function (): void {
        Route::get('meta', [StaffAccessController::class, 'meta'])->name('staff-access.meta');

        Route::get('{staff}/effective', [StaffAccessController::class, 'effective'])->name('staff-access.effective');
        Route::put('{staff}/overrides', [StaffAccessController::class, 'setOverrides'])->name('staff-access.overrides');
        Route::get('{staff}/pin', [StaffAccessController::class, 'revealPin'])->name('staff-access.pin.reveal');
        Route::post('{staff}/pin', [StaffAccessController::class, 'setPin'])->name('staff-access.pin.set');
        Route::delete('{staff}/pin', [StaffAccessController::class, 'clearPin'])->name('staff-access.pin.clear');
        Route::post('{staff}/send-reset-link', [StaffAccessController::class, 'sendResetLink'])->name('staff-access.reset-link');
        Route::post('{staff}/terminate', [StaffAccessController::class, 'terminate'])->name('staff-access.terminate');
        Route::post('{staff}/activate', [StaffAccessController::class, 'activate'])->name('staff-access.activate');
    });

    Route::post('api/v1/roles/{role}/copy', [RoleController::class, 'copy'])->name('roles.copy');

    /* ---- Personel taklidi ("test için giriş") — oturum-tabanlı ---- */
    Route::post('api/v1/staff/stop-impersonate', [ImpersonationController::class, 'stop'])->name('staff.impersonate.stop');
    Route::post('api/v1/staff/{staff}/impersonate', [ImpersonationController::class, 'start'])->name('staff.impersonate.start');
});
