<?php

use App\Modules\Billing\Http\Controllers\SaasBillingActionController;
use App\Modules\Billing\Http\Controllers\SaasCheckoutController;
use App\Modules\Billing\Http\Controllers\SaasPaymentCallbackController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| SaaS Abonelik ÖDEME GEÇİDİ (A2 devamı) — iyzico/PayTR/manuel çerçevesi
|--------------------------------------------------------------------------
| bootstrap/app.php `then:` bloğuna EKLENMEDİ (talimat gereği elle
| düzenlenmedi) — kaydetmek için `then:` closure'ının SONUNA şu satırı ekle
| (routes/billing_saas.php satırının hemen altı uygun bir yerdir):
|
|   \Illuminate\Support\Facades\Route::group([], __DIR__.'/../routes/saas_payment.php');
|
| Üç bölüm:
|  1) Kiracı ödeme başlatma ("Şimdi Öde"): `auth:web` İLE fakat `tenant`
|     middleware'i OLMADAN. Askıya alınmış işletme zaten EnsureTenantContext
|     tarafından /hesap-askida'ya yönlendirildiği için, ödeme başlatma ucu
|     `tenant` middleware zincirinin İÇİNDE OLAMAZ — aksi halde askıdaki
|     işletme ödeme sayfasına HİÇ ULAŞAMAZ (döngü).
|  2) Sağlayıcı webhook/callback'i: TAMAMEN middleware'siz (CSRF dışı,
|     oturumsuz) — kimlik = sağlayıcı imzası (bkz. Payments/Providers/*
|     ::verifyCallback). routes/payments.php'deki POS callback ucuyla AYNI
|     desen (o dosya da "web" grubunun dışındadır).
|  3) Süper-admin aksiyonları: routes/billing_saas.php ile AYNI
|     auth:web+superadmin+prefix('yonetim') deseni.
*/

Route::middleware('auth:web')->group(function (): void {
    Route::get('/odeme/{invoice}', [SaasCheckoutController::class, 'start'])
        ->whereNumber('invoice')->name('saas.pay');
    Route::get('/odeme', [SaasCheckoutController::class, 'payLatest'])->name('saas.pay.latest');
    Route::get('/odeme/sonuc', [SaasCheckoutController::class, 'result'])->name('saas.pay.result');
});

Route::post('/api/v1/public/saas-payments/callback/{provider}', [SaasPaymentCallbackController::class, 'handle'])
    ->where('provider', '[a-z_]{1,30}')
    ->name('saas.payment.callback');

Route::middleware(['auth:web', 'superadmin'])->prefix('yonetim')->name('superadmin.')->group(function (): void {
    Route::post('/faturalama/{invoice}/odendi', [SaasBillingActionController::class, 'markPaid'])
        ->whereNumber('invoice')->name('billing.mark-paid');
    Route::get('/faturalama/{invoice}/link', [SaasBillingActionController::class, 'payLink'])
        ->whereNumber('invoice')->name('billing.pay-link');
});
