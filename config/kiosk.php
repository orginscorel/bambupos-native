<?php

/**
 * Kiosk yüzeyi ayarları (Faz 8).
 */
return [

    // Oturum zaman aşımı: bu kadar saniye dokunulmazsa uyarı çıkar,
    // uyarı süresi de dolarsa ekran SIFIRLANIR (tam sayfa yeniden yükleme —
    // sepet/isim dahil tüm istemci durumu yok olur; hiçbir şey saklanmaz).
    'idle_seconds' => (int) env('KIOSK_IDLE_SECONDS', 90),
    'warn_seconds' => (int) env('KIOSK_WARN_SECONDS', 20),

    // Fiş ekranı bu süre sonunda kendini "yeni sipariş"e sıfırlar.
    'receipt_seconds' => (int) env('KIOSK_RECEIPT_SECONDS', 45),

    // Cihaz kalp atışı aralığı (sağlık rozeti + uzaktan kilit yoklaması).
    'heartbeat_seconds' => (int) env('KIOSK_HEARTBEAT_SECONDS', 45),

    // Sipariş ucu hız sınırı (token+IP başına / dakika).
    'order_rate_per_minute' => (int) env('KIOSK_ORDER_RATE_PER_MINUTE', 10),

    // Bekleyen POS ödemesi için istemci sorgu penceresi.
    'payment_poll_seconds' => (int) env('KIOSK_PAYMENT_POLL_SECONDS', 5),
    'payment_poll_max' => (int) env('KIOSK_PAYMENT_POLL_MAX', 12),
];
