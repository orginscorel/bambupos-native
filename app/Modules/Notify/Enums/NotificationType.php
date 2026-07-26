<?php

namespace App\Modules\Notify\Enums;

/**
 * §8 Bildirim olay tipleri — TEK KAYNAK katalog.
 *
 * Her tip; etiketi, kategorisi, VARSAYILAN kanalları (in-app / push) ve ALICI
 * YÖNLENDİRME kuralını (hangi izin/istasyon/rol alır) taşır. Dispatcher bu
 * metadatayı okur; Profil "Bildirimler" ekranı ve yönetici politikası da
 * buradan türetilir. Yeni olay = yeni case + burada tanımı.
 *
 * ALICI MODELİ (RecipientResolver):
 *  - targetPermissions(): alıcı bu izinlerden EN AZ BİRİNE sahip olmalı.
 *  - includeManagers(): yöneticiler (reports.view/staff.manage/settings.manage)
 *    her hâlükârda dahildir ("yönetim hepsini görür — kendi şubesi").
 *  - laneScoped(): true ise context['lane'] (kitchen|barista) ile istasyon
 *    ailesine göre süzülür (Mutfak kalemi baristayı, barista kalemi mutfağı
 *    RAHATSIZ ETMEZ; kısıtsız/çok-istasyonlu kullanıcı ikisini de alır).
 *  Tüm alıcılar ŞUBE KAPSAMIYLA süzülür (BranchContext; notifications.branch_id).
 */
enum NotificationType: string
{
    /** Yeni sipariş kuyruğa düştü → o şubenin mutfak/barista personeli. */
    case OrderPlaced = 'order_placed';

    /** Kalem HAZIR, teslim bekliyor → o şubenin komileri. */
    case ItemReady = 'item_ready';

    /** Komi teslim aldı ama süresinde masaya vermedi (§11 SLA) → komi + yönetici. */
    case DeliverySlaBreach = 'delivery_sla_breach';

    /** Sipariş servis edildi → yönetici (varsayılan sessiz). */
    case OrderServed = 'order_served';

    /** Kalem kritik eşiğin altına düştü → depo yetkilisi + yönetici. */
    case LowStock = 'low_stock';

    /** Yaklaşan onaylı rezervasyon → garson/host + yönetici. */
    case ReservationUpcoming = 'reservation_upcoming';

    /** Rezervasyon no-show (gelmedi) → garson/host + yönetici. */
    case ReservationNoShow = 'reservation_no_show';

    public function label(): string
    {
        return match ($this) {
            self::OrderPlaced => 'Yeni sipariş',
            self::ItemReady => 'Sipariş hazır (teslim bekliyor)',
            self::DeliverySlaBreach => 'Teslim gecikmesi (SLA)',
            self::OrderServed => 'Servis edildi',
            self::LowStock => 'Düşük stok uyarısı',
            self::ReservationUpcoming => 'Yaklaşan rezervasyon',
            self::ReservationNoShow => 'Rezervasyon gelmedi (no-show)',
        };
    }

    /** Profil ekranındaki kısa açıklama. */
    public function description(): string
    {
        return match ($this) {
            self::OrderPlaced => 'Şubene yeni bir sipariş düştüğünde (mutfak/barista).',
            self::ItemReady => 'Bir ürün hazırlanıp teslim beklerken (komi).',
            self::DeliverySlaBreach => 'Teslim alınan ürün süresinde masaya götürülmediğinde.',
            self::OrderServed => 'Bir sipariş masaya servis edildiğinde.',
            self::LowStock => 'Bir stok kalemi kritik eşiğin altına indiğinde.',
            self::ReservationUpcoming => 'Onaylı bir rezervasyonun saati yaklaştığında.',
            self::ReservationNoShow => 'Rezervasyon sahibi gelmediğinde.',
        };
    }

    /** Profil ekranında gruplama başlığı. */
    public function category(): string
    {
        return match ($this) {
            self::OrderPlaced, self::OrderServed => 'orders',
            self::ItemReady, self::DeliverySlaBreach => 'kitchen',
            self::LowStock => 'stock',
            self::ReservationUpcoming, self::ReservationNoShow => 'reservations',
        };
    }

    public static function categoryLabel(string $category): string
    {
        return match ($category) {
            'orders' => 'Siparişler',
            'kitchen' => 'Mutfak & Teslim',
            'stock' => 'Stok',
            'reservations' => 'Rezervasyonlar',
            default => $category,
        };
    }

    public function defaultInApp(): bool
    {
        // OrderServed dışında hepsi varsayılan açık.
        return $this !== self::OrderServed;
    }

    public function defaultPush(): bool
    {
        // Gürültüyü azaltmak için: yeni-sipariş push varsayılan açık (operasyon
        // kritik); servis-edildi push varsayılan kapalı.
        return $this !== self::OrderServed;
    }

    /** @return array<int, string> alıcı bu izinlerden en az birine sahip olmalı */
    public function targetPermissions(): array
    {
        return match ($this) {
            self::OrderPlaced => ['kds.view'],
            self::ItemReady => ['kds.deliver'],
            self::DeliverySlaBreach => ['kds.deliver'],
            self::OrderServed => ['orders.view'],
            self::LowStock => ['stock.view', 'stock.adjust'],
            self::ReservationUpcoming, self::ReservationNoShow => ['reservations.view', 'reservations.manage'],
        };
    }

    public function includeManagers(): bool
    {
        // Yeni sipariş & hazır & servis: operasyon personeline gider; yönetici
        // panoyu izler (gürültü olmasın). SLA/stok/rezervasyon: yönetici de alır.
        return match ($this) {
            self::OrderPlaced, self::ItemReady, self::OrderServed => false,
            default => true,
        };
    }

    /** İstasyon kulvarına (kitchen/barista) göre süzülsün mü? */
    public function laneScoped(): bool
    {
        return $this === self::OrderPlaced;
    }

    /** Zil/push için ikon adı (AppIcon glifi). */
    public function icon(): string
    {
        return match ($this) {
            self::OrderPlaced => 'orders',
            self::ItemReady => 'check',
            self::DeliverySlaBreach => 'clock',
            self::OrderServed => 'check',
            self::LowStock => 'package',
            self::ReservationUpcoming, self::ReservationNoShow => 'calendar',
        };
    }

    /**
     * Frontend (Profil tercihleri + yönetici politikası) için katalog dökümü.
     *
     * @return array<int, array{
     *   key:string, label:string, description:string, category:string,
     *   category_label:string, default_in_app:bool, default_push:bool
     * }>
     */
    public static function catalog(): array
    {
        return array_map(fn (self $t): array => [
            'key' => $t->value,
            'label' => $t->label(),
            'description' => $t->description(),
            'category' => $t->category(),
            'category_label' => self::categoryLabel($t->category()),
            'default_in_app' => $t->defaultInApp(),
            'default_push' => $t->defaultPush(),
        ], self::cases());
    }
}
