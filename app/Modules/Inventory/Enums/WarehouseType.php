<?php

namespace App\Modules\Inventory\Enums;

/** Depo türleri (§17.1). */
enum WarehouseType: string
{
    case Main = 'main';
    case Branch = 'branch';
    case Kitchen = 'kitchen';
    case Bar = 'bar';
    case Cold = 'cold';
    case Consumable = 'consumable';
    case Custom = 'custom';

    public function label(): string
    {
        return match ($this) {
            self::Main => 'Ana depo',
            self::Branch => 'Şube deposu',
            self::Kitchen => 'Mutfak deposu',
            self::Bar => 'Bar deposu',
            self::Cold => 'Soğuk hava deposu',
            self::Consumable => 'Sarf malzeme deposu',
            self::Custom => 'Özel depo',
        };
    }

    /** @return array<int, array{value: string, label: string}> */
    public static function options(): array
    {
        return array_map(fn (self $t) => ['value' => $t->value, 'label' => $t->label()], self::cases());
    }
}
