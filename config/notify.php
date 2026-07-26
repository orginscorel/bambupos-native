<?php

/*
|--------------------------------------------------------------------------
| §8 Bildirim & Push (Notify modülü)
|--------------------------------------------------------------------------
| Web Push (VAPID) yapılandırması + operasyonel parametreler. Olay tipi
| kataloğu (etiket / alıcı yönlendirme / varsayılan kanallar) TİPLİ erişim
| için `App\Modules\Notify\Enums\NotificationType` enum'ında tutulur.
*/

return [

    // Web Push açık mı? VAPID anahtarı yoksa ya da testte KAPALI (dış ağ yok).
    // Panel-içi zil/bildirim kaydı bundan bağımsız her zaman çalışır.
    'push_enabled' => (bool) env('NOTIFY_PUSH_ENABLED', true),

    // VAPID anahtar çifti (.env — VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY).
    // Üret: php -r 'echo json_encode(Minishlink\WebPush\VAPID::createVapidKeys());'
    'vapid' => [
        'subject' => env('VAPID_SUBJECT', 'mailto:hello@example.com'),
        'public_key' => env('VAPID_PUBLIC_KEY', ''),
        'private_key' => env('VAPID_PRIVATE_KEY', ''),
    ],

    // Kısa dedup penceresi (sn): aynı alıcıya aynı olay bu süre içinde
    // ikinci kez YAZILMAZ (idempotent/atomik-yaklaşık, best-effort).
    'dedup_window_seconds' => 60,

    // Komi teslim SLA'sı (§11): kalem teslim ALINDIKTAN sonra bu süre içinde
    // masaya TESLİM edilmezse ihlal bildirimi (komi + yönetici) + rapor logu.
    'delivery_sla_minutes' => 2,

    // Rezervasyon "yaklaşıyor" bildirimi: reserved_at bu kadar dk kaldığında.
    'reservation_lead_minutes' => 30,

    // Zil listesinde tutulan azami kayıt (okunmuş dahil) — panelde gösterim.
    'bell_list_limit' => 30,
];
