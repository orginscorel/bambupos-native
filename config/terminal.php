<?php

/**
 * Terminal yüzeyi ayarları (§13 Faz 3 — panelden lisanslı terminal kurulumu).
 *
 * `license.default_limit`: yeni/mevcut bir kiracının, kendi başına HİÇBİR
 * özel değer atanmamışken sahip olacağı "makul varsayılan" terminal lisans
 * sayısı (bkz. migration add_terminal_license_limit_to_tenants_table).
 * Bilinçli olarak PLANA (config/pricing_saas.php) bağlı DEĞİLDİR — o türetme
 * ileride bambumpos SaaS tarafında ayrıca kurulabilir; burada yalnız
 * tenant-setting/config iskeleti kurulur.
 *
 * `tenants.terminal_license_limit` sütunu NULL ise sınırsızdır (bilinçli
 * istisna); dolu ise TerminalDeviceController::store() bu değeri aşan yeni
 * cihaz eklemeyi 422 ile reddeder (bkz. App\Modules\Terminal\Support\TerminalLicense).
 */
return [

    'license' => [
        'default_limit' => (int) env('TERMINAL_LICENSE_DEFAULT_LIMIT', 5),
    ],

];
