<?php

use App\Modules\Portal\Http\Controllers\PortalClockController;
use App\Modules\Portal\Http\Controllers\PortalPageController;
use App\Modules\Portal\Http\Controllers\PortalProfileController;
use App\Modules\Portal\Http\Controllers\PortalReportController;
use App\Modules\Commission\Http\Controllers\PortalEarningsController;
use App\Modules\Delivery\Http\Controllers\PortalDeliveryController;
use App\Modules\Portal\Http\Controllers\PortalLeaveController;
use App\Modules\Portal\Http\Controllers\PortalScheduleController;
use App\Modules\Portal\Support\Portal;
use App\Modules\StaffTasks\Http\Controllers\PortalTaskController;
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
        Route::get('/panelim', [PortalPageController::class, 'dashboard'])->name('portal.dashboard');
        Route::get('/mesaim', [PortalPageController::class, 'shift'])->name('portal.shift');
        Route::get('/takvim', [PortalPageController::class, 'schedule'])->name('portal.schedule');
        Route::get('/gorevlerim', [PortalPageController::class, 'tasks'])->name('portal.tasks');
        Route::get('/teslimatlarim', [PortalPageController::class, 'deliveries'])
            ->middleware('feature:delivery')->name('portal.deliveries');
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

            // Takvim: kişinin kendi yaklaşan vardiyaları
            Route::get('schedule', [PortalScheduleController::class, 'index'])->name('portal.schedule.data');

            // Mesai geçmişi: kişinin son mesai kayıtları
            Route::get('history', [PortalClockController::class, 'history'])->name('portal.history');

            // İzin talebi: kendi taleplerini listele / oluştur / iptal et
            Route::get('leave-requests', [PortalLeaveController::class, 'index'])->name('portal.leaves.index');
            Route::post('leave-requests', [PortalLeaveController::class, 'store'])->name('portal.leaves.store');
            Route::post('leave-requests/{leave}/cancel', [PortalLeaveController::class, 'cancel'])->name('portal.leaves.cancel');

            // Görevlerim: kişiye atanan görevler + durum güncelle (kendi görevi)
            Route::get('tasks', [PortalTaskController::class, 'index'])->name('portal.tasks.data');
            Route::post('tasks/{task}/status', [PortalTaskController::class, 'updateStatus'])->name('portal.tasks.status');

            // Raporlarım
            Route::get('reports', [PortalReportController::class, 'index'])->name('portal.reports.data');

            // Teslimatlarım (kurye) — feature: delivery
            Route::middleware('feature:delivery')->group(function (): void {
                Route::get('deliveries', [PortalDeliveryController::class, 'index'])->name('portal.deliveries.data');
                Route::post('deliveries/{delivery}/status', [PortalDeliveryController::class, 'updateStatus'])
                    ->whereNumber('delivery')->name('portal.deliveries.status');
            });

            // Kazancım (prim) — feature: commission
            Route::get('earnings', [PortalEarningsController::class, 'index'])
                ->middleware('feature:commission')->name('portal.earnings');

            // Profilim
            Route::put('profile', [PortalProfileController::class, 'update'])->name('portal.profile.update');
            Route::put('profile/pin', [PortalProfileController::class, 'updatePin'])->name('portal.profile.pin');
        });
    });
