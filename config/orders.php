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

];
