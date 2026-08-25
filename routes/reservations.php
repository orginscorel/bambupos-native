<?php

use App\Modules\Reservations\Http\Controllers\PublicReservationController;
use App\Modules\Reservations\Http\Controllers\ReservationController;
use App\Modules\Reservations\Http\Controllers\ReservationLinkController;
use App\Modules\Reservations\Http\Controllers\ReservationPageController;
use App\Modules\Reservations\Http\Controllers\WaitlistController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Reservations modülü (Faz-9): rezervasyon + bekleme listesi
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| Public uç BİLİNÇLİ oturumsuz (ADR-008): kimlik yalnız QR token; hız
| sınırı controller içinde (token+IP). Müşteri onay/iptal sayfası (/r/…)
| web grubundadır (form + CSRF) ama oturum İSTEMEZ; kimlik = opak
| confirmation_token.
*/

/* ---- Panel Inertia sayfaları ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/rezervasyonlar', [ReservationPageController::class, 'index'])->name('panel.reservations.index');
    Route::get('/rezervasyonlar/bekleme-listesi', [ReservationPageController::class, 'waitlist'])->name('panel.reservations.waitlist');
    Route::get('/rezervasyonlar/no-show', [ReservationPageController::class, 'noShowReport'])->name('panel.reservations.no-show');
});

/* ---- Panel API'si ----
 * feature:reservations (denetim #panel-mgmt-3, bkz. routes/shifts.php'deki
 * aynı düzeltme): "Rezervasyon" eklentisi kapalıysa TÜM grup 404 — eskiden
 * yalnız ReservationPageController::featureGate() sayfayı gate'liyordu,
 * ReservationController/WaitlistController (CRUD + hatırlatma + depozito)
 * kapalıyken de açıktı. */
Route::middleware(['web', 'auth:web', 'tenant', 'feature:reservations'])->prefix('api/v1/reservations')->group(function (): void {

    Route::get('/', [ReservationController::class, 'index'])->name('reservations.index');
    Route::get('availability', [ReservationController::class, 'availability'])->name('reservations.availability');
    Route::get('reports/no-show', [ReservationController::class, 'noShowReport'])->name('reservations.reports.no-show');

    // Bekleme listesi
    Route::get('waitlist', [WaitlistController::class, 'index'])->name('reservations.waitlist.index');
    Route::post('waitlist', [WaitlistController::class, 'store'])->name('reservations.waitlist.store');
    Route::put('waitlist/{entry}', [WaitlistController::class, 'update'])->whereNumber('entry')->name('reservations.waitlist.update');
    Route::post('waitlist/{entry}/status', [WaitlistController::class, 'setStatus'])->whereNumber('entry')->name('reservations.waitlist.status');

    // Rezervasyon CRUD + durum makinesi
    Route::post('/', [ReservationController::class, 'store'])->name('reservations.store');
    Route::get('{reservation}', [ReservationController::class, 'show'])->whereNumber('reservation')->name('reservations.show');
    Route::put('{reservation}', [ReservationController::class, 'update'])->whereNumber('reservation')->name('reservations.update');
    Route::delete('{reservation}', [ReservationController::class, 'destroy'])->whereNumber('reservation')->name('reservations.destroy');
    Route::post('{reservation}/status', [ReservationController::class, 'setStatus'])->whereNumber('reservation')->name('reservations.status');
    Route::post('{reservation}/deposit', [ReservationController::class, 'setDeposit'])->whereNumber('reservation')->name('reservations.deposit');
    Route::post('{reservation}/remind', [ReservationController::class, 'remind'])->whereNumber('reservation')->name('reservations.remind');
});

/* ---- Public (oturumsuz) QR rezervasyon talebi — public menü buraya bağlanır ---- */
Route::post('/api/v1/public/reservations', [PublicReservationController::class, 'store'])
    ->name('reservations.public.store');

/* ---- Müşteri onay/iptal bağlantısı (e-postadaki link) ---- */
Route::middleware('web')->group(function (): void {
    Route::get('/r/{token}', [ReservationLinkController::class, 'show'])
        ->where('token', '[a-f0-9]{40}')
        ->name('reservations.link.show');
    Route::post('/r/{token}/iptal', [ReservationLinkController::class, 'cancel'])
        ->where('token', '[a-f0-9]{40}')
        ->name('reservations.link.cancel');
});
