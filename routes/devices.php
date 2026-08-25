<?php

use App\Modules\Devices\Http\Controllers\AuthorizedDeviceController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| İzinli Cihazlar modülü (A3 — KDS/Kiosk cihaz kilidi temeli)
|--------------------------------------------------------------------------
| BU DOSYA HENÜZ bootstrap/app.php'nin `then:` bloğuna KAYDEDİLMEMİŞTİR
| (görev kuralı: bootstrap/app.php'ye dokunulmadı). Kaydetmek için ana
| oturumun bootstrap/app.php `then:` kapanışına aşağıdaki satırı eklemesi
| gerekir (diğer domain dosyalarıyla aynı desen, kds.php'nin hemen altına
| eklenmesi mantıklı):
|
|   \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/devices.php');
|
| Ayrıca EnsureDeviceAuthorized middleware'inin `device:kind[,routeParam]`
| takma adıyla çağrılabilmesi için bootstrap/app.php `withMiddleware()`
| içindeki `$middleware->alias([...])` dizisine şu satırın eklenmesi gerekir:
|
|   'device' => \App\Modules\Devices\Http\Middleware\EnsureDeviceAuthorized::class,
|
| Bu dosyadaki rotalar (panel sayfası + JSON API) bu alan olmadan da çalışır;
| alias YALNIZ EnsureDeviceAuthorized'ın kds.php/kiosk.php/terminal.php gibi
| BAŞKA rota dosyalarında `device:kds` şeklinde kullanılabilmesi için gerekir.
*/

Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    Route::get('/panel/izinli-cihazlar', function () {
        abort_unless(request()->user()->hasPermission('devices.view')
            || request()->user()->hasPermission('devices.manage'), 403);

        return Inertia::render('Panel/Devices/Index');
    })->name('panel.devices.index');

    Route::prefix('api/v1/devices')->group(function (): void {
        Route::get('/', [AuthorizedDeviceController::class, 'index'])->name('devices.index');
        // Senkron görünüm: gerçek terminal+kiosk cihazları + bağlantı/QR + kilit durumu.
        Route::get('synced', [AuthorizedDeviceController::class, 'synced'])->name('devices.synced');
        Route::post('release-by-token', [AuthorizedDeviceController::class, 'releaseByToken'])->name('devices.release-by-token');
        Route::post('transfer-by-token', [AuthorizedDeviceController::class, 'transferByToken'])->name('devices.transfer-by-token');
        // §13 Faz 3: Terminaller/İzinli Cihazlar ekranlarından tek-tık device_lock aç/kapa
        // (Eklentiler ekranıyla AYNI depo — bkz. AuthorizedDeviceController::toggleLock).
        Route::post('lock-feature', [AuthorizedDeviceController::class, 'toggleLock'])->name('devices.lock-feature');
        Route::post('/', [AuthorizedDeviceController::class, 'store'])->name('devices.store');
        Route::put('{device}', [AuthorizedDeviceController::class, 'update'])->whereNumber('device')->name('devices.update');
        Route::post('{device}/revoke', [AuthorizedDeviceController::class, 'revoke'])->whereNumber('device')->name('devices.revoke');
        Route::post('{device}/reactivate', [AuthorizedDeviceController::class, 'reactivate'])->whereNumber('device')->name('devices.reactivate');
        Route::post('{device}/release', [AuthorizedDeviceController::class, 'release'])->whereNumber('device')->name('devices.release');
        Route::post('{device}/transfer', [AuthorizedDeviceController::class, 'transfer'])->whereNumber('device')->name('devices.transfer');
        Route::delete('{device}', [AuthorizedDeviceController::class, 'destroy'])->whereNumber('device')->name('devices.destroy');
    });
});
