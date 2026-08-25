<?php

namespace App\Modules\Kiosk\Support;

/**
 * Kiosk özellik bayrağı — TEK kontrol noktası.
 *
 * Kiosk yüzeyine (public ekran + panel yönetimi) her giriş bu kapıdan geçer.
 * İşletme bazında tek yerden aç/kapa yapılabilmesini sağlar — çağrı noktalarını
 * dağıtmadan.
 *
 * §9 feature-flag: `tenant_features` tablosu + FeatureService üzerinden gerçek
 * tenant bazlı kontrol yapılır (2026-07-26'da devreye alındı — bkz. MODULE_MAP
 * §9). Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → public ekran
 * 404, panel linki gizli.
 */
class KioskFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // §9 feature-flag deposuna bağlı: yönetici "Eklentiler"den kapatırsa
        // kiosk public ekranı 404, panel linki gizlenir (ADR: kapalı=yok).
        return \App\Modules\Settings\Support\Features::enabled($tenantId, 'kiosk');
    }
}
