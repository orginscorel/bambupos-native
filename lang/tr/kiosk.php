<?php

/**
 * Kiosk hata/kilit sayfaları (resources/views/kiosk/error.blade.php,
 * resources/views/kiosk/locked.blade.php). Bu sayfalar cihaz token'ı daha
 * çözülmeden / kiosk.js yüklenmeden ÖNCE sunucuda render edilir; dolayısıyla
 * kiosk.js'in kendi TR/EN arayüz sözlüğünden (public/assets/kiosk.js I18N)
 * BAĞIMSIZDIR. Dil KioskScreenController::show içinde ?lang= ile erken
 * çözülür (QR tarafı PublicMenuController ile aynı desen).
 *
 * PARİTE: tr/en/de dosyaları AYNI anahtar setini içerir (bkz. lang/{en,de}/kiosk.php).
 */
return [
    // <title> — 3 dilde de aynı kalabilir (cihaz jargonu).
    'error_title' => 'Kiosk',
    'locked_title_suffix' => 'Kiosk',

    // error.blade.php — 410 (rotasyonla geçersiz kılınmış / pasif kayıt)
    'error_gone_heading' => 'Bu kiosk kaydı artık geçerli değil',
    'error_gone_body' => 'Cihaz adresi yenilendi veya kayıt pasife alındı. Lütfen işletme yöneticisinden yeni kiosk adresini isteyin.',

    // error.blade.php — 429 (rate limit)
    'error_throttled_heading' => 'Çok sık istek',
    'error_throttled_body' => 'Lütfen kısa bir süre sonra tekrar deneyin.',

    // error.blade.php — 404 (geçersiz/bilinmeyen token veya kapalı özellik)
    'error_invalid_heading' => 'Kiosk bulunamadı',
    'error_invalid_body' => 'Bu adres geçerli bir kiosk cihazına ait değil.',

    // locked.blade.php — panelden kilitlenmiş cihaz (kendini yoklayan ekran)
    'locked_heading' => ':device geçici olarak kapalı',
    'locked_body' => 'Bu kiosk yönetici tarafından kilitlendi. Lütfen personele başvurun.',
];
