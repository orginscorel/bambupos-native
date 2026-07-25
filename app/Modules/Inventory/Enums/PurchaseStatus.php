<?php

namespace App\Modules\Inventory\Enums;

/** Satın alma akışı (§17.6): talep → teklif → sipariş → mal kabul. */
enum PurchaseStatus: string
{
    case Draft = 'draft';                       // satın alma talebi
    case Quoted = 'quoted';                     // teklif alındı
    case Ordered = 'ordered';                   // sipariş verildi
    case PartiallyReceived = 'partially_received';
    case Received = 'received';
    case Cancelled = 'cancelled';

    public function canTransitionTo(self $to): bool
    {
        return match ($this) {
            self::Draft => in_array($to, [self::Quoted, self::Ordered, self::Cancelled], true),
            self::Quoted => in_array($to, [self::Ordered, self::Cancelled], true),
            self::Ordered => in_array($to, [self::PartiallyReceived, self::Received, self::Cancelled], true),
            self::PartiallyReceived => in_array($to, [self::Received], true),
            default => false,
        };
    }

    /** Mal kabul yapılabilir mi? */
    public function receivable(): bool
    {
        return in_array($this, [self::Ordered, self::PartiallyReceived], true);
    }

    public function label(): string
    {
        return match ($this) {
            self::Draft => 'Talep',
            self::Quoted => 'Teklif alındı',
            self::Ordered => 'Sipariş verildi',
            self::PartiallyReceived => 'Kısmen teslim',
            self::Received => 'Teslim alındı',
            self::Cancelled => 'İptal',
        };
    }

    public function variant(): string
    {
        return match ($this) {
            self::Draft => 'neutral',
            self::Quoted => 'info',
            self::Ordered => 'primary',
            self::PartiallyReceived => 'warning',
            self::Received => 'success',
            self::Cancelled => 'danger',
        };
    }

    /** @return array<int, array{value: string, label: string, variant: string}> */
    public static function options(): array
    {
        return array_map(fn (self $s) => ['value' => $s->value, 'label' => $s->label(), 'variant' => $s->variant()], self::cases());
    }
}
