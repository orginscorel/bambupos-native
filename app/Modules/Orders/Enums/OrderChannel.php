<?php

namespace App\Modules\Orders\Enums;

/** Sipariş kanalı (prompt §12.2): masa · paket · gel-al · kiosk · QR. */
enum OrderChannel: string
{
    case Table = 'table';
    case Package = 'package';
    case Pickup = 'pickup';
    case Kiosk = 'kiosk';
    case Qr = 'qr';

    /** Masaya bağlı (masa durumunu süren) kanallar. */
    public function usesTable(): bool
    {
        return $this === self::Table || $this === self::Qr;
    }

    /** Catalog'daki kanal-özel fiyat kolonu (NULL ise price_minor geçerli). */
    public function priceColumn(): ?string
    {
        return match ($this) {
            self::Table => null, // salon satışı = liste fiyatı
            self::Package => 'package_price_minor',
            self::Pickup => 'package_price_minor',
            self::Kiosk => 'kiosk_price_minor',
            self::Qr => 'qr_price_minor',
        };
    }

    /** Ürünün `channels` JSON'undaki anahtar (masa/gel-al POS satışıdır). */
    public function catalogChannelKey(): string
    {
        return match ($this) {
            self::Table, self::Pickup => 'pos',
            self::Package => 'package',
            self::Kiosk => 'kiosk',
            self::Qr => 'qr',
        };
    }

    public function label(): string
    {
        return match ($this) {
            self::Table => 'Masa',
            self::Package => 'Paket',
            self::Pickup => 'Gel-Al',
            self::Kiosk => 'Kiosk',
            self::Qr => 'QR',
        };
    }

    public function icon(): string
    {
        return match ($this) {
            self::Table => 'utensils',
            self::Package => 'cart',
            self::Pickup => 'store',
            self::Kiosk => 'dashboard',
            self::Qr => 'qr-code',
        };
    }

    /*
     * KAYNAK (nereden) — kanal iki farklı bilgiyi karıştırıyordu: siparişin
     * NEREDEN geldiği (garson/kiosk/QR) ile NASIL servis edileceği
     * (masada/gel-al/paket). "Nasıl" bilgisi artık yapısal ServiceType'tan
     * gelir; kanalın Package/Pickup değerleri de aslında POS'ta personelin
     * açtığı sipariştir (kaynak = Garson). Bu üçlü, Board/Detail'de
     * ServiceType etiketiyle ÇAKIŞMAYAN tek "kaynak" rozetini besler
     * (#3: "paket" çift görünmesin).
     */

    /** Siparişin KAYNAĞI (nereden): Garson (salon/POS) · Kiosk · QR. */
    public function sourceLabel(): string
    {
        return match ($this) {
            self::Table, self::Package, self::Pickup => 'Garson',
            self::Kiosk => 'Kiosk',
            self::Qr => 'QR',
        };
    }

    public function sourceIcon(): string
    {
        return match ($this) {
            self::Table, self::Package, self::Pickup => 'users',
            self::Kiosk => 'dashboard',
            self::Qr => 'qr-code',
        };
    }

    public function sourceVariant(): string
    {
        return match ($this) {
            self::Table, self::Package, self::Pickup => 'info',
            self::Kiosk => 'neutral',
            self::Qr => 'success',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Table => 'info',
            self::Package => 'warning',
            self::Pickup => 'primary',
            self::Kiosk => 'neutral',
            self::Qr => 'success',
        };
    }

    /** @return array<int, array{value: string, label: string, icon: string, variant: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => [
            'value' => $s->value,
            'label' => $s->label(),
            'icon' => $s->icon(),
            'variant' => $s->variant(),
        ], self::cases());
    }
}
