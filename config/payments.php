<?php

use App\Modules\Payments\Providers\CardPresentProvider;
use App\Modules\Payments\Providers\CashProvider;
use App\Modules\Payments\Providers\MockPosProvider;
use App\Modules\Payments\Providers\SandboxPosProvider;

/**
 * Payments modülü ayarları (Faz-5, ADR-010).
 * GERÇEK sağlayıcı bağlanmaz; terminal yöntemleri varsayılan MOCK'tur.
 */
return [

    // Terminal (kredi/banka kartı) yöntemlerinin varsayılan sağlayıcısı.
    'default_terminal_provider' => env('PAYMENTS_TERMINAL_PROVIDER', 'mock'),

    // Sağlayıcı kayıt defteri: anahtar → adapter sınıfı.
    'providers' => [
        'cash' => CashProvider::class,
        'card_present' => CardPresentProvider::class,
        'mock' => MockPosProvider::class,
        'sandbox' => SandboxPosProvider::class,
    ],

    // Nakit yuvarlama adımı (kuruş): kalan tutar bu adıma yuvarlanabilir.
    'cash_rounding_step_minor' => (int) env('PAYMENTS_CASH_ROUNDING_STEP', 25),

    // Adisyon başına izin verilen en büyük mutlak yuvarlama (kuruş).
    'max_rounding_minor' => 99,

    // Callback zaman damgası toleransı (saniye) — replay penceresi.
    'callback_tolerance_seconds' => (int) env('PAYMENTS_CALLBACK_TOLERANCE', 300),

    // Servis bedeli üst sınırı (yüzde).
    'max_service_charge_percent' => 20.0,

    'mock' => [
        // Boşsa app.key'den türetilir (yalnız mock için kabul edilebilir).
        'secret' => env('PAYMENTS_MOCK_SECRET', ''),
        // Terminal simülasyon gecikmesi (ms, 0-2000).
        'delay_ms' => (int) env('PAYMENTS_MOCK_DELAY_MS', 0),
    ],

    'sandbox' => [
        'base_url' => env('PAYMENTS_SANDBOX_BASE_URL', ''),
        'api_key' => env('PAYMENTS_SANDBOX_API_KEY', ''),
        'secret' => env('PAYMENTS_SANDBOX_SECRET', ''),
    ],

];
