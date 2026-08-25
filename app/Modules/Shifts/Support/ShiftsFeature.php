<?php

namespace App\Modules\Shifts\Support;

/**
 * Shifts (Vardiya/Mesai) özellik bayrağı — TEK kontrol noktası.
 *
 * Vardiya panel yüzeyine her giriş bu kapıdan geçer (Kiosk/Reservation deseni).
 * İşletme bazında tek yerden aç/kapa yapılabilmesini sağlar — çağrı noktalarını
 * dağıtmadan.
 *
 * §9 feature-flag: `tenant_features` tablosu + FeatureService üzerinden gerçek
 * tenant bazlı kontrol yapılır (2026-07-26'da devreye alındı — bkz. MODULE_MAP
 * §9). Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → panel rotaları
 * 404, menü linki gizli.
 */
class ShiftsFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // §9 feature-flag deposuna bağlı: kapalıysa vardiya/mesai panel rotaları
        // 404, menü linki gizlenir (ADR: kapalı=yok).
        return \App\Modules\Settings\Support\Features::enabled($tenantId, 'shifts');
    }
}
