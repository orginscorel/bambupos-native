<?php

namespace App\Modules\Reservations\Support;

/**
 * Rezervasyon özellik bayrağı — TEK kontrol noktası (KioskFeature deseni).
 *
 * Rezervasyon yüzeyine (panel yönetimi + public QR talebi) her giriş bu
 * kapıdan geçer. İşletme bazında tek yerden aç/kapa yapılabilmesini sağlar —
 * çağrı noktalarını dağıtmadan.
 *
 * §9 feature-flag: `tenant_features` tablosu + FeatureService üzerinden gerçek
 * tenant bazlı kontrol yapılır (2026-07-26'da devreye alındı — bkz. MODULE_MAP
 * §9). Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → public uç ve
 * panel rotası 404, menü linki gizli.
 */
class ReservationFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // §9 feature-flag deposuna bağlı: kapalıysa panel+public rezervasyon
        // rotaları 404, menü linki gizlenir (ADR: kapalı=yok).
        return \App\Modules\Settings\Support\Features::enabled($tenantId, 'reservations');
    }
}
