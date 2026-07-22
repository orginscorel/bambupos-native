<?php

use App\Modules\Catalog\Http\Controllers\ProductController;
use App\Modules\Identity\Http\Controllers\AuditLogController;
use App\Modules\Identity\Http\Controllers\LoginController;
use App\Modules\Identity\Http\Controllers\PasswordResetController;
use App\Modules\Identity\Http\Controllers\PinController;
use App\Modules\Identity\Http\Controllers\RoleController;
use App\Modules\Identity\Http\Controllers\SessionController;
use App\Modules\Identity\Http\Controllers\StaffController;
use App\Modules\Identity\Http\Controllers\TwoFactorController;
use App\Modules\Ordering\Http\Controllers\CustomerController;
use App\Modules\Ordering\Http\Controllers\OrderController;
use App\Modules\Reporting\Http\Controllers\ReportController;
use App\Modules\Tables\Http\Controllers\TableController;
use Illuminate\Support\Facades\Route;

Route::prefix('api/v1')->group(function (): void {

    /* ---- Misafir uçları (kendi içlerinde rate-limit'li) ---- */
    Route::post('auth/login', [LoginController::class, 'store'])->name('auth.login');
    Route::post('auth/two-factor-challenge', [TwoFactorController::class, 'challenge'])->name('auth.2fa.challenge');
    Route::post('auth/pin-login', [PinController::class, 'login'])->name('auth.pin-login');
    Route::post('auth/forgot-password', [PasswordResetController::class, 'forgot'])->name('auth.forgot');
    Route::post('auth/reset-password', [PasswordResetController::class, 'reset'])->name('auth.reset');

    /* ---- Oturumlu + kiracı bağlamlı uçlar ---- */
    Route::middleware(['auth:web', 'tenant'])->group(function (): void {
        Route::post('auth/logout', [LoginController::class, 'destroy'])->name('auth.logout');

        // Aktif cihaz/oturum yönetimi
        Route::get('auth/sessions', [SessionController::class, 'index'])->name('auth.sessions');
        Route::delete('auth/sessions/{hashedId}', [SessionController::class, 'destroy'])->name('auth.sessions.destroy');
        Route::post('auth/logout-other-devices', [SessionController::class, 'destroyOthers'])->name('auth.sessions.others');

        // PIN + 2FA
        Route::post('auth/pin', [PinController::class, 'store'])->name('auth.pin.set');
        Route::post('auth/two-factor/enable', [TwoFactorController::class, 'enable'])->name('auth.2fa.enable');
        Route::post('auth/two-factor/confirm', [TwoFactorController::class, 'confirm'])->name('auth.2fa.confirm');
        Route::delete('auth/two-factor', [TwoFactorController::class, 'disable'])->name('auth.2fa.disable');

        // Kimlik & yetki
        Route::apiResource('staff', StaffController::class)->parameters(['staff' => 'staff']);
        Route::apiResource('roles', RoleController::class);
        Route::get('audit-logs', [AuditLogController::class, 'index'])->name('audit-logs.index');

        // Faz-1 alan iskeleti (izolasyon kanıtı; sonraki fazlar genişletir)
        Route::apiResource('products', ProductController::class);
        Route::apiResource('customers', CustomerController::class);
        Route::apiResource('tables', TableController::class)->parameters(['tables' => 'table']);
        Route::post('tables/{table}/rotate-qr', [TableController::class, 'rotateQr'])->name('tables.rotate-qr');
        Route::apiResource('orders', OrderController::class)->only(['index', 'store', 'show']);
        Route::post('orders/{order}/cancel', [OrderController::class, 'cancel'])->name('orders.cancel');
        Route::get('reports/summary', [ReportController::class, 'summary'])->name('reports.summary');
    });
});
