<?php

namespace App\Modules\Payments\Enums;

/**
 * Ödeme durumu. KURAL (prompt §15): terminale tutar göndermek ödeme
 * tamamlandı DEMEK DEĞİLDİR — yalnız doğrulanmış terminal cevabı /
 * imzalı callback / sorgu sonucu Pending → Succeeded geçirir.
 * Geçişler transitions() ile sınırlıdır; Succeeded'a İKİNCİ geçiş yoktur
 * (çift işleme koruması katmanlarından biri).
 */
enum PaymentStatus: string
{
    case Pending = 'pending';                       // bekliyor (terminal cevabı/callback)
    case Succeeded = 'succeeded';                   // başarılı (adisyona işledi)
    case Failed = 'failed';                         // başarısız (adisyonu KAPATMAZ)
    case Cancelled = 'cancelled';                   // iptal/void (tahsilat geri alındı)
    case PartiallyRefunded = 'partially_refunded';  // kısmi iade edildi
    case Refunded = 'refunded';                     // tamamı iade edildi

    /** @return array<int, self> */
    public function transitions(): array
    {
        return match ($this) {
            self::Pending => [self::Succeeded, self::Failed, self::Cancelled],
            self::Succeeded => [self::Cancelled, self::PartiallyRefunded, self::Refunded],
            self::PartiallyRefunded => [self::PartiallyRefunded, self::Refunded],
            self::Failed, self::Cancelled, self::Refunded => [],
        };
    }

    public function canTransitionTo(self $to): bool
    {
        return in_array($to, $this->transitions(), true);
    }

    /** Adisyona işlemiş (paid_minor'da sayılan) durumlar. */
    public function countsAsCollected(): bool
    {
        return in_array($this, [self::Succeeded, self::PartiallyRefunded, self::Refunded], true);
    }

    public function label(): string
    {
        return match ($this) {
            self::Pending => 'Bekliyor',
            self::Succeeded => 'Başarılı',
            self::Failed => 'Başarısız',
            self::Cancelled => 'İptal',
            self::PartiallyRefunded => 'Kısmi iade',
            self::Refunded => 'İade edildi',
        };
    }

    public function icon(): string
    {
        return match ($this) {
            self::Pending => 'alert-circle',
            self::Succeeded => 'check-circle',
            self::Failed => 'x-circle',
            self::Cancelled => 'x-circle',
            self::PartiallyRefunded, self::Refunded => 'arrow-left',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Pending => 'warning',
            self::Succeeded => 'success',
            self::Failed, self::Cancelled => 'danger',
            self::PartiallyRefunded, self::Refunded => 'info',
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
