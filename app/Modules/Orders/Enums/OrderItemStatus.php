<?php

namespace App\Modules\Orders\Enums;

/**
 * KALEM durumu — sipariş bütününden bağımsız akar (prompt §12.1):
 * içecek "servis edildi" iken ana yemek "hazırlanıyor" olabilir.
 *
 * Kural: yalnız İLERİ yönde geçiş (sıra atlanabilir: içecek doğrudan
 * servis edilebilir) + servis edilmemiş kalem iptal edilebilir.
 */
enum OrderItemStatus: string
{
    case Placed = 'placed';
    case SentToStation = 'sent_to_station';
    case Accepted = 'accepted';
    case Preparing = 'preparing';
    case Ready = 'ready';
    case Served = 'served';
    case Cancelled = 'cancelled';

    /** İleri-yön sırası (Cancelled hariç). */
    private function rank(): int
    {
        return match ($this) {
            self::Placed => 0,
            self::SentToStation => 1,
            self::Accepted => 2,
            self::Preparing => 3,
            self::Ready => 4,
            self::Served => 5,
            self::Cancelled => 99,
        };
    }

    public function canTransitionTo(self $to): bool
    {
        if ($this === self::Cancelled || $this === $to) {
            return false; // terminal / yerinde sayma
        }

        if ($to === self::Cancelled) {
            return $this !== self::Served; // servis edilen kalem iptal edilemez (ikram/iade yolu ayrı)
        }

        return $to->rank() > $this->rank(); // yalnız ileri; ara adım atlanabilir
    }

    public function isActive(): bool
    {
        return $this !== self::Cancelled;
    }

    public function label(): string
    {
        return match ($this) {
            self::Placed => 'Alındı',
            self::SentToStation => 'İstasyonda',
            self::Accepted => 'Kabul edildi',
            self::Preparing => 'Hazırlanıyor',
            self::Ready => 'Hazır',
            self::Served => 'Servis edildi',
            self::Cancelled => 'İptal',
        };
    }

    public function icon(): string
    {
        return match ($this) {
            self::Placed => 'orders',
            self::SentToStation => 'arrow-right',
            self::Accepted => 'check',
            self::Preparing => 'chef-hat',
            self::Ready => 'check-circle',
            self::Served => 'utensils',
            self::Cancelled => 'x-circle',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Placed, self::SentToStation, self::Accepted => 'info',
            self::Preparing => 'warning',
            self::Ready, self::Served => 'success',
            self::Cancelled => 'danger',
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
