<?php

use App\Modules\Terminal\Http\Controllers\TerminalDeviceController;
use App\Modules\Terminal\Http\Controllers\TerminalOperatorController;
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

    /* ---- §13 Faz C: Aktif operatör (paylaşımlı cihazda "kim çalışıyor") ----
     | DİKKAT: bu sabit yollar /terminal/{token} joker rotasından ÖNCE
     | tanımlanmalıdır — "operators"/"operator" ifadeleri token deseniyle
     | ([A-Za-z2-7]) eşleşir; önce gelen kazanır. Yalnız gizli terminal
     | (is_terminal) oturumu erişebilir (controller abort_unless ile zorlar);
     | EnsureTerminalLocked `terminal/*` yollarını zaten serbest bırakır. */
    Route::get('/terminal/operators', [TerminalOperatorController::class, 'index'])
        ->name('terminal.operators.index');
    Route::post('/terminal/operator', [TerminalOperatorController::class, 'store'])
        ->name('terminal.operator.set');
    Route::post('/terminal/operator/clear', [TerminalOperatorController::class, 'clear'])
        ->name('terminal.operator.clear');
    Route::get('/terminal/operator/stats', [TerminalOperatorController::class, 'stats'])
        ->name('terminal.operator.stats');

    // §13 Faz D: ANLIK uzaktan kilit (BUG #3 düzeltmesi). heartbeat()
    // 'locked' döndüğünde istemci (useTerminalHeartbeat) tam sayfa buraya
    // yönlendirir — token GEREKMEZ (oturumdaki user_id'den çözülür), bu
    // yüzden token joker rotasından ÖNCE tanımlanmalıdır (yukarıdaki
    // operators/operator uyarısıyla aynı sebep).
    Route::get('/terminal/relock', [TerminalScreenController::class, 'relock'])
        ->middleware('auth:web')
        ->name('terminal.relock');

    Route::get('/terminal/{token}', [TerminalScreenController::class, 'show'])
        ->where('token', '[A-Za-z2-7]{1,64}')
        ->name('terminal.screen');

    // Cihazda personel değişimi / kilit: terminal oturumunu kapatır.
    Route::post('/terminal/logout', [TerminalScreenController::class, 'logout'])
        ->name('terminal.logout');

    // Kalp atışı: istasyon ekranı açıkken last_seen_at tazelenir (panel "Çevrimiçi"
    // rozeti doğru kalsın). Yalnız oturumlu terminal kullanıcısı.
    Route::post('/terminal/heartbeat', [TerminalScreenController::class, 'heartbeat'])
        ->middleware('auth:web')
        ->name('terminal.heartbeat');
});

/* ---- Panel: terminal cihaz yönetimi (terminals.manage) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->group(function (): void {

    Route::get('/panel/terminaller', function () {
        // §9 feature-flag: kapalıysa terminaller hiç yok (ADR: kapalı=404).
        abort_unless(\App\Modules\Settings\Support\Features::enabled(
            (int) request()->user()?->tenant_id, 'terminals'
        ), 404);

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
