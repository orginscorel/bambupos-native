<?php

namespace App\Modules\Kiosk\Support;

/**
 * Kiosk özellik bayrağı — TEK kontrol noktası.
 *
 * Kiosk yüzeyine (public ekran + panel yönetimi) her giriş bu kapıdan geçer.
 * Amaç: ileride (MODULE_MAP §9 "Eklentiler / feature-flag") kiosk'u işletme
 * bazında tek yerden aç/kapa yapabilmek — çağrı noktalarını dağıtmadan.
 *
 * TODO(§9 feature-flag): `features` tablosu/servisi geldiğinde burada
 * tenant bazlı gerçek kontrol yapılacak (ör. Features::enabled($tenantId,
 * 'kiosk')). Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) →
 * public ekran 404, panel linki gizli. Tablo henüz YOK; yer tutucu true.
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
