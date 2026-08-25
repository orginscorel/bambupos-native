<?php

use App\Modules\Billing\Payments\Providers\IyzicoProvider;
use App\Modules\Billing\Payments\Providers\ManualProvider;
use App\Modules\Billing\Payments\Providers\PaytrProvider;

/*
|--------------------------------------------------------------------------
| SaaS abonelik ÖDEME GEÇİDİ ayarları (BamBumPOS'un işletmelerden aylık
| ücreti TAHSİL ETMESİ — platform geliri). config/payments.php (POS/kasa,
| işletme İÇİ müşteri tahsilatı) ile KARIŞTIRILMAMALI — bambaşka bir
| entegrasyon, bambaşka bir sağlayıcı haritası, bambaşka bir gelir kalemi.
|--------------------------------------------------------------------------
| VARSAYILAN 'manual': hiçbir kimlik bilgisi girilmemişse (aşağıdaki TÜM
| env değişkenleri boş) canlı tahsilat YAPILMAZ — süper-admin panelden
| elle "ödendi" işaretler (bkz. BillingService::markPaid,
| SaasBillingActionController::markPaid). GERÇEK ANAHTAR BU DOSYAYA ASLA
| YAZILMAZ — yalnız .env'den okunur.
|--------------------------------------------------------------------------
*/

return [

    // Aktif sağlayıcı: manual | iyzico | paytr
    'provider' => env('SAAS_PAYMENT_PROVIDER', 'manual'),

    // Sağlayıcı kayıt defteri: anahtar → adapter sınıfı (ProviderRegistry deseniyle
    // aynı mantık — bkz. app/Modules/Payments/Providers/ProviderRegistry.php).
    'providers' => [
        'manual' => ManualProvider::class,
        'iyzico' => IyzicoProvider::class,
        'paytr' => PaytrProvider::class,
    ],

    // iyzico Checkout Form (HPP) — bkz. IyzicoProvider. Sandbox varsayılan;
    // canlıya geçişte IYZICO_BASE_URL=https://api.iyzipay.com yapılır.
    'iyzico' => [
        'api_key' => env('IYZICO_API_KEY', ''),
        'secret' => env('IYZICO_SECRET', ''),
        'base_url' => env('IYZICO_BASE_URL', 'https://sandbox-api.iyzipay.com'),
    ],

    // PayTR iFrame/Link API — bkz. PaytrProvider.
    'paytr' => [
        'merchant_id' => env('PAYTR_MERCHANT_ID', ''),
        'merchant_key' => env('PAYTR_MERCHANT_KEY', ''),
        'merchant_salt' => env('PAYTR_MERCHANT_SALT', ''),
        // 1 = PayTR test modu (gerçek tahsilat yapılmaz, sağlayıcı tarafında test kartlarıyla çalışır).
        'test_mode' => (bool) env('PAYTR_TEST_MODE', false),
    ],

    // Webhook imza zaman damgası toleransı (sn) — sağlayıcıların bazı imza
    // şemalarında zaman damgası yoktur; yalnız kullanılan yerde uygulanır.
    'callback_tolerance_seconds' => (int) env('SAAS_PAYMENT_CALLBACK_TOLERANCE', 300),

];
