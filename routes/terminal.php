<?php

use App\Modules\Terminal\Http\Controllers\TerminalDeviceController;
use App\Modules\Terminal\Http\Controllers\TerminalScreenController;
use Illuminate\Support\Facades\Route;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Terminal modülü (§13, Faz A): istasyon cihaz modu (kilitli terminaller)
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| Yaklaşım (en az riskli): her terminal cihazı = GİZLİ, istasyona-atanmış bir
| kullanıcı + opak token. /terminal/{token} token'la oto-giriş yapar (mevcut
| auth); kilitli mod (nav gizli + rota koruması + rozet) devreye girer.
|
| Giriş rotası "web" grubundadır (oturum gerekir) — kimlik yalnız token.
| Terminal kullanıcısı normal (e-posta/PIN) giriş yapamaz; tek kapı budur.
*/

/* ---- Terminal girişi (token'la oto-giriş) ---- */
Route::middleware('web')->group(function (): void {
    Route::get('/terminal/{token}', [TerminalScreenController::class, 'show'])
        ->where('token', '[A-Za-z2-7]{1,64}')
        ->name('terminal.screen');

    // Cihazda personel değişimi / kilit: terminal oturumunu kapatır.
    Route::post('/terminal/logout', [TerminalScreenController::class, 'logout'])
        ->name('terminal.logout');
});

/* ---- Panel: terminal cihaz yönetimi (terminals.manage) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    Route::get('/panel/terminaller', function () {
        abort_unless(request()->user()->hasPermission('terminals.view')
            || request()->user()->hasPermission('terminals.manage'), 403);

        return Inertia::render('Panel/Terminals/Index');
    })->name('panel.terminals.index');

    Route::prefix('api/v1/terminals')->group(function (): void {
        Route::get('devices', [TerminalDeviceController::class, 'index'])->name('terminals.devices.index');
        Route::post('devices', [TerminalDeviceController::class, 'store'])->name('terminals.devices.store');
        Route::put('devices/{device}', [TerminalDeviceController::class, 'update'])->name('terminals.devices.update');
        Route::post('devices/{device}/rotate-token', [TerminalDeviceController::class, 'rotateToken'])->name('terminals.devices.rotate');
        Route::post('devices/{device}/lock', [TerminalDeviceController::class, 'lock'])->name('terminals.devices.lock');
        Route::post('devices/{device}/unlock', [TerminalDeviceController::class, 'unlock'])->name('terminals.devices.unlock');
        Route::delete('devices/{device}', [TerminalDeviceController::class, 'destroy'])->name('terminals.devices.destroy');
    });
});
