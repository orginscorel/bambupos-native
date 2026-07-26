<?php

namespace App\Modules\Inventory\Support;

/**
 * Stok/Depo özellik bayrağı — TEK kontrol noktası (KioskFeature/
 * ReservationFeature deseni).
 *
 * Inventory yüzeyine (panel ekranları + sipariş↔stok köprüsü) her giriş bu
 * kapıdan geçebilsin diye vardır. Amaç: MODULE_MAP §9 "Eklentiler /
 * feature-flag" altyapısı gelince stok modülünü işletme bazında tek yerden
 * aç/kapa yapmak — çağrı noktalarını dağıtmadan.
 *
 * TODO(§9 feature-flag): `features` tablosu/servisi geldiğinde burada tenant
 * bazlı gerçek kontrol yapılacak (ör. Features::enabled($tenantId, 'stock')).
 * Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → panel ekranları
 * 404, menü linki gizli, sipariş köprüsü sessiz durur. Tablo henüz YOK;
 * yer tutucu true.
 */
class InventoryFeature
{
    public static function enabled(?int $tenantId = null): bool
    {
        // §9 feature-flag deposuna bağlı: kapalıysa panel stok ekranları 404,
        // menü linki gizli, sipariş↔stok köprüsü sessiz durur (ADR: kapalı=yok).
        return \App\Modules\Settings\Support\Features::enabled($tenantId, 'inventory');
    }
}
