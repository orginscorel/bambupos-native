<?php

/**
 * Ayar modülü (app/Modules/Settings) yapılandırması.
 */
return [

    /*
    |--------------------------------------------------------------------------
    | Platform işletmecisi kiracı kimliği
    |--------------------------------------------------------------------------
    | Platform düzeyi varsayılan e-posta ayarını YALNIZ bu kiracının
    | (settings.manage iznine sahip) kullanıcıları düzenleyebilir.
    | Boş bırakılırsa platform varsayılanı panelden düzenlenemez;
    | diğer işletmeler her durumda yalnız kendi override'larını yönetir.
    */
    'platform_tenant_id' => env('PLATFORM_TENANT_ID'),

    /*
    |--------------------------------------------------------------------------
    | E-posta bağlantı testi
    |--------------------------------------------------------------------------
    | max_attempts / decay_seconds: kullanıcı başına deneme sınırı (kötüye
    | kullanım / SSRF taramasını caydırır). timeout_cap: test isteğinin
    | sunucuyu dakikalarca bekletmemesi için üst sınır (saniye).
    */
    'mail_test' => [
        'max_attempts' => 3,
        'decay_seconds' => 60,
        'timeout_cap' => 15,
    ],

    /*
    |--------------------------------------------------------------------------
    | İşletme (platform-dışı kiracı) SMTP kısıtları — SSRF önlemi
    |--------------------------------------------------------------------------
    | Platform dışı kiracılar yalnız yaygın SMTP portlarına ve genel (public)
    | adreslere bağlanabilir; iç ağ adresleri reddedilir.
    */
    'tenant_smtp_ports' => [25, 465, 587, 2525],

];
