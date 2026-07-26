<?php

use App\Modules\Portal\Http\Controllers\PortalClockController;
use App\Modules\Portal\Http\Controllers\PortalPageController;
use App\Modules\Portal\Http\Controllers\PortalProfileController;
use App\Modules\Portal\Http\Controllers\PortalReportController;
use App\Modules\Portal\Support\Portal;
use Illuminate\Session\Middleware\AuthenticateSession;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Personel Portalı (Faz 1) — host-farkındalıklı self-servis
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| HOST KAPSAMI: tüm portal rotaları config('portal.host') alan adına
| (Route::domain) bağlıdır → yalnız portal host'unda (ya da Host header ile
| test edilirken) eşleşir; panel host'unda TANIMLI DEĞİL (izolasyon).
|
| KALICI OTURUM: portal girişi uzun ömürlü remember-me kullanır (LoginController
| portal host'unda remember=true'yu zorlar) + idle-timeout yok. Oto-kapanma
| YALNIZ 3 durumda:
|   (a) pasife alınma / işten çıkarma → EnsureUserIsActive (global web) düşürür,
|   (b) parola değişimi → AuthenticateSession (bu grupta) oturumu geçersiz kılar.
| Bu üçü DIŞINDA oturum kalıcıdır. Panel host'unun oturum davranışı DEĞİŞMEZ
| (AuthenticateSession YALNIZ portal grubunda uygulanır).
*/

Route::domain(Portal::host())
    ->middleware(['web', 'auth:web', 'tenant', AuthenticateSession::class, \App\Modules\Portal\Http\Middleware\EnsurePortalAccess::class])
    ->group(function (): void {

        /* ---- Inertia sayfaları (portal layout) ---- */
        Route::get('/mesaim', [PortalPageController::class, 'shift'])->name('portal.shift');
        Route::get('/raporlarim', [PortalPageController::class, 'reports'])->name('portal.reports');
        Route::get('/profilim', [PortalPageController::class, 'profile'])->name('portal.profile');

        /* ---- JSON uçları (PIN'siz — kişinin KENDİ oturumu) ---- */
        Route::prefix('api/v1/portal')->group(function (): void {
            // Mesaim: kişinin kendi mesai/mola/tuvalet uçları
            Route::get('state', [PortalClockController::class, 'state'])->name('portal.state');
            Route::post('clock/in', [PortalClockController::class, 'clockIn'])->name('portal.clock.in');
            Route::post('clock/out', [PortalClockController::class, 'clockOut'])->name('portal.clock.out');
            Route::post('break/start', [PortalClockController::class, 'breakStart'])->name('portal.break.start');
            Route::post('break/end', [PortalClockController::class, 'breakEnd'])->name('portal.break.end');

            // Raporlarım
            Route::get('reports', [PortalReportController::class, 'index'])->name('portal.reports.data');

            // Profilim
            Route::put('profile', [PortalProfileController::class, 'update'])->name('portal.profile.update');
            Route::put('profile/pin', [PortalProfileController::class, 'updatePin'])->name('portal.profile.pin');
        });
    });
