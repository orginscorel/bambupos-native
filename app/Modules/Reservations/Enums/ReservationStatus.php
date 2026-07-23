<?php

namespace App\Modules\Reservations\Enums;

/**
 * Rezervasyon durum makinesi (prompt §9.2).
 *
 * Akış: Talep alındı → Onay bekliyor → Onaylandı → (Gecikti) → Müşteri
 * geldi → Masaya alındı → Tamamlandı; her aktif durumdan İptal; onaylı/
 * gecikmiş durumdan Gelmedi (no-show).
 *
 * Erişilebilirlik: durum yalnız renkle anlatılmaz — ikon + metin birlikte.
 */
enum ReservationStatus: string
{
    case Requested = 'requested';           // talep alındı (QR/telefon)
    case PendingConfirmation = 'pending';   // onay bekliyor
    case Confirmed = 'confirmed';           // onaylandı → masa 'reserved'
    case Late = 'late';                     // saati geçti, müşteri gelmedi (henüz no-show değil)
    case Arrived = 'arrived';               // müşteri geldi (karşılamada)
    case Seated = 'seated';                 // masaya alındı
    case Completed = 'completed';           // tamamlandı
    case Cancelled = 'cancelled';           // iptal
    case NoShow = 'no_show';                // gelmedi

    public function label(): string
    {
        return match ($this) {
            self::Requested => 'Talep alındı',
            self::PendingConfirmation => 'Onay bekliyor',
            self::Confirmed => 'Onaylandı',
            self::Late => 'Gecikti',
            self::Arrived => 'Müşteri geldi',
            self::Seated => 'Masaya alındı',
            self::Completed => 'Tamamlandı',
            self::Cancelled => 'İptal',
            self::NoShow => 'Gelmedi (no-show)',
        };
    }

    /** Tasarım sistemindeki AppIcon adı. */
    public function icon(): string
    {
        return match ($this) {
            self::Requested => 'inbox',
            self::PendingConfirmation => 'bell',
            self::Confirmed => 'check-circle',
            self::Late => 'alert-triangle',
            self::Arrived => 'user',
            self::Seated => 'users',
            self::Completed => 'check',
            self::Cancelled => 'x-circle',
            self::NoShow => 'alert-circle',
        };
    }

    /** BaseBadge renk varyantı. */
    public function variant(): string
    {
        return match ($this) {
            self::Requested => 'info',
            self::PendingConfirmation => 'warning',
            self::Confirmed => 'primary',
            self::Late => 'danger',
            self::Arrived => 'info',
            self::Seated => 'success',
            self::Completed => 'success',
            self::Cancelled => 'neutral',
            self::NoShow => 'danger',
        };
    }

    /** Masa/çakışma hesabında yer TUTAN durumlar (kapanmışlar tutmaz). */
    public static function blocking(): array
    {
        return [
            self::Requested, self::PendingConfirmation, self::Confirmed,
            self::Late, self::Arrived, self::Seated,
        ];
    }

    /** @return array<int, string> */
    public static function blockingValues(): array
    {
        return array_map(fn (self $s) => $s->value, self::blocking());
    }

    public function isFinal(): bool
    {
        return in_array($this, [self::Completed, self::Cancelled, self::NoShow], true);
    }

    /** @return array<int, self> izinli hedef durumlar */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Requested => [self::PendingConfirmation, self::Confirmed, self::Cancelled],
            self::PendingConfirmation => [self::Confirmed, self::Cancelled],
            self::Confirmed => [self::Late, self::Arrived, self::Seated, self::Cancelled, self::NoShow],
            self::Late => [self::Arrived, self::Seated, self::Cancelled, self::NoShow],
            self::Arrived => [self::Seated, self::Cancelled, self::Completed],
            self::Seated => [self::Completed, self::Cancelled],
            self::Completed, self::Cancelled, self::NoShow => [],
        };
    }

    public function canTransitionTo(self $target): bool
    {
        return in_array($target, $this->allowedTransitions(), true);
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
