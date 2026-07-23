<?php

namespace App\Modules\Reservations\Enums;

enum WaitlistStatus: string
{
    case Waiting = 'waiting';     // sırada
    case Notified = 'notified';   // "masanız hazır" — müşteri çağrıldı
    case Seated = 'seated';       // masaya alındı
    case Cancelled = 'cancelled'; // vazgeçti
    case Expired = 'expired';     // çağrıldı ama gelmedi

    public function label(): string
    {
        return match ($this) {
            self::Waiting => 'Bekliyor',
            self::Notified => 'Çağrıldı',
            self::Seated => 'Masaya alındı',
            self::Cancelled => 'Vazgeçti',
            self::Expired => 'Gelmedi',
        };
    }

    public function icon(): string
    {
        return match ($this) {
            self::Waiting => 'inbox',
            self::Notified => 'bell',
            self::Seated => 'users',
            self::Cancelled => 'x-circle',
            self::Expired => 'alert-circle',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Waiting => 'warning',
            self::Notified => 'info',
            self::Seated => 'success',
            self::Cancelled => 'neutral',
            self::Expired => 'danger',
        };
    }

    public function isOpen(): bool
    {
        return in_array($this, [self::Waiting, self::Notified], true);
    }

    /** @return array<int, array{value: string, label: string, icon: string, variant: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => [
            'value' => $s->value, 'label' => $s->label(), 'icon' => $s->icon(), 'variant' => $s->variant(),
        ], self::cases());
    }
}
