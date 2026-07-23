<?php

namespace App\Modules\Reservations\Enums;

/** Kapora takibi (tutar kuruş-integer olarak reservations.deposit_minor'da). */
enum DepositStatus: string
{
    case None = 'none';           // kapora istenmedi
    case Pending = 'pending';     // istendi, henüz alınmadı
    case Paid = 'paid';           // alındı
    case Refunded = 'refunded';   // iade edildi
    case Forfeited = 'forfeited'; // yandı (no-show / geç iptal)

    public function label(): string
    {
        return match ($this) {
            self::None => 'Kapora yok',
            self::Pending => 'Bekleniyor',
            self::Paid => 'Alındı',
            self::Refunded => 'İade edildi',
            self::Forfeited => 'Yandı',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::None => 'neutral',
            self::Pending => 'warning',
            self::Paid => 'success',
            self::Refunded => 'info',
            self::Forfeited => 'danger',
        };
    }

    /** @return array<int, array{value: string, label: string, variant: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => [
            'value' => $s->value, 'label' => $s->label(), 'variant' => $s->variant(),
        ], self::cases());
    }
}
