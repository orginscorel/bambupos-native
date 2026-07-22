<?php

namespace App\Modules\Venue\Enums;

/** Salon/alan türleri. */
enum AreaType: string
{
    case Indoor = 'indoor';
    case Terrace = 'terrace';
    case Garden = 'garden';
    case Bar = 'bar';
    case Vip = 'vip';
    case Takeaway = 'takeaway';
    case Kiosk = 'kiosk';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::Indoor => 'İç salon',
            self::Terrace => 'Teras',
            self::Garden => 'Bahçe',
            self::Bar => 'Bar',
            self::Vip => 'VIP',
            self::Takeaway => 'Paket servis',
            self::Kiosk => 'Kiosk alanı',
            self::Other => 'Diğer',
        };
    }

    /** @return array<int, array{value: string, label: string}> */
    public static function options(): array
    {
        return array_map(fn (self $t) => ['value' => $t->value, 'label' => $t->label()], self::cases());
    }
}
