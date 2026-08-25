<?php

use App\Modules\Payments\Http\Controllers\CashController;
use App\Modules\Payments\Http\Controllers\PaymentCallbackController;
use App\Modules\Payments\Http\Controllers\PaymentController;
use App\Modules\Payments\Http\Controllers\PaymentPageController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Payments modülü (Faz-5, ADR-010): kasa + ödeme + POS adapter
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğunda kaydedilir.
|
| Callback ucu BİLİNÇLİ olarak "web" grubunun DIŞINDADIR: sağlayıcı
| sunucu-sunucu POST eder; kimlik = HMAC imza + zaman damgası
| (MockPosProvider::verifyCallback), oturum/CSRF uygulanmaz.
*/

/* ---- Panel Inertia sayfaları (kasiyer/kasa ekranları) ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('panel')->group(function (): void {
    Route::get('/kasa', [PaymentPageController::class, 'cashier'])->name('panel.payments.cashier');
    Route::get('/kasa/yonetim', [PaymentPageController::class, 'cashDesk'])->name('panel.payments.cashdesk');
    Route::get('/kasa/z/{session}', [PaymentPageController::class, 'zReport'])
        ->whereNumber('session')->name('panel.payments.zreport');
});

/* ---- Panel API'si ---- */
Route::middleware(['web', 'auth:web', 'tenant'])->prefix('api/v1')->group(function (): void {

    // Kasiyer ekranı: ödeme bekleyen adisyonlar + terminal durumu
    Route::get('payments/pending-orders', [PaymentController::class, 'pendingOrders'])->name('payments.pending-orders');
    Route::get('payments/terminal-status', [PaymentController::class, 'terminalStatus'])->name('payments.terminal-status');

    // POS ENTEGRATÖR yönetimi: işletme kendi cihazını/sağlayıcısını seçer (settings.manage)
    Route::get('payments/pos-integration', [\App\Modules\Payments\Http\Controllers\PosIntegrationController::class, 'show'])->name('payments.pos.show');
    Route::put('payments/pos-integration', [\App\Modules\Payments\Http\Controllers\PosIntegrationController::class, 'update'])->name('payments.pos.update');
    Route::post('payments/pos-integration/test', [\App\Modules\Payments\Http\Controllers\PosIntegrationController::class, 'test'])->name('payments.pos.test');

    // Adisyon ödemeleri (Idempotency-Key desteklenir)
    Route::get('orders/{order}/payments', [PaymentController::class, 'index'])->whereNumber('order')->name('payments.index');
    Route::post('orders/{order}/payments', [PaymentController::class, 'store'])->whereNumber('order')->name('payments.store');

    // Servis bedeli (tutar otoritesi OrderService'te)
    Route::post('orders/{order}/service-charge', [\App\Modules\Payments\Http\Controllers\ServiceChargeController::class, 'store'])
        ->whereNumber('order')->name('payments.service-charge.store');
    Route::delete('orders/{order}/service-charge', [\App\Modules\Payments\Http\Controllers\ServiceChargeController::class, 'destroy'])
        ->whereNumber('order')->name('payments.service-charge.destroy');

    // Ödeme işlemleri
    Route::post('payments/{payment}/query', [PaymentController::class, 'query'])->whereNumber('payment')->name('payments.query');
    Route::post('payments/{payment}/void', [PaymentController::class, 'void'])->whereNumber('payment')->name('payments.void');
    Route::post('payments/{payment}/refund', [PaymentController::class, 'refund'])->whereNumber('payment')->name('payments.refund');

    // Kasa yönetimi (prompt §16)
    Route::get('cash/registers', [CashController::class, 'registers'])->name('cash.registers');
    Route::post('cash/registers', [CashController::class, 'storeRegister'])->name('cash.registers.store');
    Route::get('cash/sessions', [CashController::class, 'sessions'])->name('cash.sessions');
    Route::post('cash/sessions', [CashController::class, 'openSession'])->name('cash.sessions.open');
    Route::get('cash/sessions/{session}', [CashController::class, 'showSession'])->whereNumber('session')->name('cash.sessions.show');
    Route::post('cash/sessions/{session}/movements', [CashController::class, 'addMovement'])->whereNumber('session')->name('cash.movements.add');
    Route::post('cash/movements/{movement}/reverse', [CashController::class, 'reverseMovement'])->whereNumber('movement')->name('cash.movements.reverse');
    Route::post('cash/sessions/{session}/close', [CashController::class, 'closeSession'])->whereNumber('session')->name('cash.sessions.close');
    Route::get('cash/sessions/{session}/report', [CashController::class, 'report'])->whereNumber('session')->name('cash.sessions.report');
});

/* ---- Sağlayıcı callback'i (oturumsuz; imza + timestamp doğrulamalı) ---- */
Route::post('/api/v1/public/payments/callback/{provider}', [PaymentCallbackController::class, 'handle'])
    ->where('provider', '[a-z_]{1,30}')
    ->name('payments.callback');
