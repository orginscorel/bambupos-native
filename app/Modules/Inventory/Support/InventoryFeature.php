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
 * Gerçek kontrol BAĞLI: Features::enabled($tenantId, 'inventory').
 * Kapalı = özellik hiç yok (ADR: kapalı=render edilmez) → panel ekranları
 * 404, menü linki gizli (nav feature:'inventory'), sipariş köprüsü sessiz durur.
 * İşletme istemezse "Eklentiler" ekranından tek tıkla kapatır.
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
