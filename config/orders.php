<?php

/**
 * Orders modülü ayarları (Faz-3).
 */
return [

    // Bu yüzdenin ÜZERİNDEKİ adisyon indirimi yönetici onayı (PIN) ister
    // (prompt §12.3). Sabit tutarlı indirimlerde eşik, adisyon toplamına
    // oranlanarak uygulanır.
    'discount_approval_threshold_percent' => (float) env('ORDERS_DISCOUNT_APPROVAL_PERCENT', 10),

    // Tek adisyona eklenebilecek en fazla kalem (kaza/istismar sigortası).
    'max_items_per_order' => 200,

    // Public (QR) sipariş ucu: token+IP başına dakikadaki istek sınırı.
    'public_rate_per_minute' => 10,

    // POS uygulaması değişim akışı (GET /api/v1/orders/degisim, 2026-10-30).
    // Her açık POS cihazı bir PHP işçisini bu süre kadar tutar (lsphp
    // kullanıcı başına 35). ŞALTER: ORDERS_DEGISIM_ACIK=false → uç 404 döner,
    // uygulamalar oturum boyunca sessizce 5 sn yoklamaya döner.
    'degisim_acik' => (bool) env('ORDERS_DEGISIM_ACIK', true),
    'degisim_long_poll_seconds' => (int) env('ORDERS_DEGISIM_LONG_POLL_SECONDS', 20),
    'degisim_long_poll_interval_ms' => (int) env('ORDERS_DEGISIM_LONG_POLL_INTERVAL_MS', 400),

];
