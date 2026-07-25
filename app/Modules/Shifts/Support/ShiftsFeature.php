<?php

namespace App\Modules\Shifts\Support;

/**
 * Shifts (Vardiya/Mesai) özellik bayrağı — TEK kontrol noktası.
 *
 * Vardiya panel yüzeyine her giriş bu kapıdan geçer (Kiosk/Reservation deseni).
 * Amaç: ileride (MODULE_MAP §9 "Eklentiler / feature-flag") vardiya modülünü
 * işletme bazında tek yerden aç/kapa yapabilmek — çağrı noktalarını dağıtmadan.
 *
 * TODO(§9 feature-flag): `features` tablosu/servisi geldiğinde burada tenant
 * bazlı gerçek kontrol yapılacak (ör. Features::enabled($tenantId, 'shifts')).
 * Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → panel rotaları 404,
 * menü linki gizli. Tablo henüz YOK; yer tutucu true.
 */
class ShiftsFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // Yer tutucu: özellik altyapısı gelene kadar vardiya her kiracıda açık.
        return true;
    }
}
