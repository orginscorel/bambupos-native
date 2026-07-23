<?php

namespace App\Modules\Reservations\Enums;

enum ReservationSource: string
{
    case Qr = 'qr';         // public menüden (oturumsuz talep)
    case Panel = 'panel';   // personel panelden açtı
    case Phone = 'phone';   // telefonla alındı

    public function label(): string
    {
        return match ($this) {
            self::Qr => 'QR menü',
            self::Panel => 'Panel',
            self::Phone => 'Telefon',
        };
    }

    /** @return array<int, array{value: string, label: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => ['value' => $s->value, 'label' => $s->label()], self::cases());
    }
}
