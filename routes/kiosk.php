<?php

use App\Modules\Kiosk\Http\Controllers\KioskDeviceController;
use App\Modules\Kiosk\Http\Controllers\KioskHeartbeatController;
use App\Modules\Kiosk\Http\Controllers\KioskOrderController;
use App\Modules\Kiosk\Http\Controllers\KioskScreenController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Kiosk modülü (Faz 8): self-servis sipariş ekranı + cihaz yönetimi
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| Public kiosk uçları BİLİNÇLİ oturumsuz ve "web" grubunun DIŞINDADIR:
| kimlik yalnız opak cihaz token'ı (ADR-008 deseni). Yanıtta Set-Cookie
| olmaz → kiosk oturumu sunucuda hiçbir müşteri izi tutmaz; sepet/isim
| tamamen istemci belleğindedir ve sıfırlama tam sayfa yeniden yüklemedir
| (§18: bir sonraki müşteri öncekinin HİÇBİR verisini göremez).
| CSRF web grubuna bağlıdır; bu uçlar token'la yazar (public orders deseni).
*/

/* ---- Kiosk ekranı (tam ekran, dokunmatik) ---- */
Route::get('/kiosk/{token}', [KioskScreenController::class, 'show'])
    ->where('token', '[A-Za-z2-7]{1,64}')
    ->name('kiosk.screen');

/* ---- Kiosk cihaz API'si (oturumsuz; kimlik = cihaz token'ı) ---- */
Route::post('/kiosk/api/orders', [KioskOrderController::class, 'store'])->name('kiosk.orders.store');
Route::post('/kiosk/api/payments/query', [KioskOrderController::class, 'queryPayment'])->name('kiosk.payments.query');
Route::post('/kiosk/api/heartbeat', [KioskHeartbeatController::class, 'store'])->name('kiosk.heartbeat');

/* ---- Panel: kiosk cihaz yönetimi (settings.manage) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    Route::get('/panel/kiosklar', function () {
        // Feature-flag kapısı (§9): özellik kapalıysa panel yönetimi de yok.
        abort_unless(\App\Modules\Kiosk\Support\KioskFeature::enabled((int) request()->user()->tenant_id), 404);
        abort_unless(request()->user()->hasPermission('kiosk.view')
            || request()->user()->hasPermission('kiosk.manage'), 403);

        return Inertia::render('Panel/Kiosk/Index');
    })->name('panel.kiosk.index');

    Route::prefix('api/v1/kiosk')->group(function (): void {
        Route::get('devices', [KioskDeviceController::class, 'index'])->name('kiosk.devices.index');
        Route::post('devices', [KioskDeviceController::class, 'store'])->name('kiosk.devices.store');
        Route::put('devices/{device}', [KioskDeviceController::class, 'update'])->name('kiosk.devices.update');
        Route::post('devices/{device}/rotate-token', [KioskDeviceController::class, 'rotateToken'])->name('kiosk.devices.rotate');
        Route::post('devices/{device}/lock', [KioskDeviceController::class, 'lock'])->name('kiosk.devices.lock');
        Route::post('devices/{device}/unlock', [KioskDeviceController::class, 'unlock'])->name('kiosk.devices.unlock');
        Route::delete('devices/{device}', [KioskDeviceController::class, 'destroy'])->name('kiosk.devices.destroy');
    });
});
