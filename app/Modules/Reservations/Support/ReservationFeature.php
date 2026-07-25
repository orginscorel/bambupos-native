<?php

namespace App\Modules\Reservations\Support;

/**
 * Rezervasyon özellik bayrağı — TEK kontrol noktası (KioskFeature deseni).
 *
 * Rezervasyon yüzeyine (panel yönetimi + public QR talebi) her giriş bu
 * kapıdan geçer. Amaç: ileride (MODULE_MAP §9 "Eklentiler / feature-flag")
 * rezervasyonu işletme bazında tek yerden aç/kapa yapabilmek — çağrı
 * noktalarını dağıtmadan.
 *
 * TODO(§9 feature-flag): `features` tablosu/servisi geldiğinde burada tenant
 * bazlı gerçek kontrol yapılacak (ör. Features::enabled($tenantId,
 * 'reservations')). Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) →
 * public uç ve panel rotası 404, menü linki gizli. Tablo henüz YOK; yer
 * tutucu true.
 */
class ReservationFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // Yer tutucu: özellik altyapısı gelene kadar rezervasyon her kiracıda açık.
        return true;
    }
}
