<?php

/**
 * Rezervasyon modülü (Faz-9) varsayılanları.
 * Süreler dakika cinsindendir; para alanları kuruş-integer'dır (ADR).
 */
return [

    // Varsayılan rezervasyon süresi (masa bu kadar süre bloke edilir).
    'default_duration_minutes' => (int) env('RESERVATION_DURATION_MINUTES', 120),

    // Temizlik/hazırlık tamponu: iki rezervasyon arasında zorunlu boşluk.
    'default_buffer_minutes' => (int) env('RESERVATION_BUFFER_MINUTES', 15),

    // Onaylı rezervasyon, başlangıçtan bu kadar dakika ÖNCE masayı
    // "Rezerve" durumuna alır (masa o an boşsa).
    'reserve_lead_minutes' => (int) env('RESERVATION_RESERVE_LEAD_MINUTES', 60),

    // Müşteri, saatinden bu kadar dakika sonra hâlâ gelmediyse rezervasyon
    // "Gecikti" olur ve masa "Rezervasyon gecikti" durumuna düşer.
    'late_grace_minutes' => (int) env('RESERVATION_LATE_GRACE_MINUTES', 15),

    // Gecikmeden bu kadar dakika sonra hâlâ gelinmediyse otomatik no-show.
    'no_show_after_minutes' => (int) env('RESERVATION_NO_SHOW_AFTER_MINUTES', 45),

    // Hatırlatma: başlangıçtan bu kadar dakika önce e-posta gönderilir
    // (panelden yapılandırılan SMTP ayarı — Settings modülü — kullanılır).
    'reminder_lead_minutes' => (int) env('RESERVATION_REMINDER_LEAD_MINUTES', 120),

    // Bekleme listesi: sıradaki her grup için kaba tahmini bekleme süresi.
    'waitlist_slot_minutes' => (int) env('RESERVATION_WAITLIST_SLOT_MINUTES', 15),

    // Public (QR) rezervasyon talebi ucu: token+IP başına dakikalık sınır.
    'public_rate_per_minute' => (int) env('RESERVATION_PUBLIC_RATE_PER_MINUTE', 5),

    // Public talepte kabul edilen en erken/en geç tarih aralığı (gün).
    'public_max_days_ahead' => (int) env('RESERVATION_PUBLIC_MAX_DAYS_AHEAD', 60),

    // Tek rezervasyonda kabul edilen en büyük kişi sayısı.
    'max_party_size' => (int) env('RESERVATION_MAX_PARTY_SIZE', 40),
];
