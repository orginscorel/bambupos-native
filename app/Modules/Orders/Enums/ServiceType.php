<?php

namespace App\Modules\Orders\Enums;

/**
 * SERVİS TİPİ (yapısal) — siparişin nasıl servis edileceği: masada,
 * gel-al ya da paket. `channel` (satış kaynağı: masa/kiosk/qr/pos) ile
 * KARIŞTIRILMAMALI: aynı kanaldan (ör. kiosk) her üç servis tipi de
 * gelebilir. Daha önce yalnız kiosk notuna gömülüydü; artık orders tablosunda
 * ayrı kolon (`service_type`) olarak tutulur ve Board/Detail/KDS tutarlı
 * "Masada / Gel-al / Paket" etiketini bu tek kaynaktan gösterir.
 */
enum ServiceType: string
{
    case DineIn = 'dine_in';     // masada servis (masa gerekir)
    case Takeaway = 'takeaway';  // gel-al (masasız)
    case Package = 'package';    // paket / kurye (masasız)

    /** Masa gerektirir mi? (gel-al/paket masasızdır) */
    public function requiresTable(): bool
    {
        return $this === self::DineIn;
    }

    /** Kanaldan makul varsayılan servis tipi (kiosk hariç: order_type verilir). */
    public static function fromChannel(OrderChannel $channel): self
    {
        return match ($channel) {
            OrderChannel::Package => self::Package,
            OrderChannel::Pickup => self::Takeaway,
            // Masa/QR salon içi; kiosk için çağıran açıkça order_type verir.
            default => self::DineIn,
        };
    }

    public function label(): string
    {
        return match ($this) {
            self::DineIn => 'Masada',
            self::Takeaway => 'Gel-al',
            self::Package => 'Paket',
        };
    }

    public function icon(): string
    {
        return match ($this) {
            self::DineIn => 'utensils',
            self::Takeaway => 'store',
            self::Package => 'cart',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::DineIn => 'info',
            self::Takeaway => 'primary',
            self::Package => 'warning',
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
