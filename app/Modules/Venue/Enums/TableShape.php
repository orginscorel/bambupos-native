<?php

namespace App\Modules\Venue\Enums;

/** Masa şekli (kroki editörü sonraki fazda bunu kullanacak). */
enum TableShape: string
{
    case Square = 'square';
    case Rectangle = 'rectangle';
    case Round = 'round';
    case Oval = 'oval';
    case BarStool = 'bar_stool';
    case Booth = 'booth';

    public function label(): string
    {
        return match ($this) {
            self::Square => 'Kare',
            self::Rectangle => 'Dikdörtgen',
            self::Round => 'Yuvarlak',
            self::Oval => 'Oval',
            self::BarStool => 'Bar taburesi',
            self::Booth => 'Loca / sedir',
        };
    }

    /** @return array<int, array{value: string, label: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => ['value' => $s->value, 'label' => $s->label()], self::cases());
    }
}
