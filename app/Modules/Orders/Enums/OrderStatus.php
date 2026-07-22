<?php

namespace App\Modules\Orders\Enums;

/**
 * Sipariş (adisyon) BÜTÜNÜNÜN durumu (prompt §12.1).
 *
 * Kalem durumları AYRIDIR (OrderItemStatus): içecek hazırken ana yemek
 * hazırlanıyor olabilir. Siparişin mutfak-aşaması durumları kalemlerden
 * TÜRETİLİR (OrderService::deriveKitchenStatus); ödeme/iptal aşamaları
 * ise doğrudan işlemle atanır. Geçersiz geçişler transitions() ile reddedilir.
 *
 * Erişilebilirlik: durum yalnız renkle anlatılmaz — ikon + metin birlikte.
 */
enum OrderStatus: string
{
    case Draft = 'draft';
    case PendingApproval = 'pending_approval';   // QR'dan gelen, garson onayı bekliyor
    case Placed = 'placed';
    case SentToStation = 'sent_to_station';
    case Accepted = 'accepted';
    case Preparing = 'preparing';
    case PartiallyReady = 'partially_ready';
    case Ready = 'ready';
    case AwaitingService = 'awaiting_service';
    case Served = 'served';
    case BillRequested = 'bill_requested';
    case PartiallyPaid = 'partially_paid';
    case Paid = 'paid';
    case Cancelled = 'cancelled';
    case Refunded = 'refunded';

    /**
     * İzinli geçişler. Anahtar yoksa o durumdan çıkış yoktur (terminal).
     *
     * @return array<int, self>
     */
    public function transitions(): array
    {
        return match ($this) {
            self::Draft => [self::PendingApproval, self::Placed, self::Cancelled],
            self::PendingApproval => [self::Placed, self::Cancelled],
            self::Placed => [self::SentToStation, self::Accepted, self::Preparing, self::PartiallyReady, self::Ready, self::Served, self::BillRequested, self::Cancelled],
            self::SentToStation => [self::Accepted, self::Preparing, self::PartiallyReady, self::Ready, self::BillRequested, self::Cancelled],
            self::Accepted => [self::Preparing, self::PartiallyReady, self::Ready, self::BillRequested, self::Cancelled],
            self::Preparing => [self::PartiallyReady, self::Ready, self::AwaitingService, self::Served, self::BillRequested, self::Cancelled],
            self::PartiallyReady => [self::Preparing, self::Ready, self::AwaitingService, self::Served, self::BillRequested, self::Cancelled],
            self::Ready => [self::AwaitingService, self::Served, self::PartiallyReady, self::Preparing, self::BillRequested, self::Cancelled],
            self::AwaitingService => [self::Served, self::BillRequested, self::Cancelled],
            self::Served => [self::BillRequested, self::PartiallyPaid, self::Paid, self::Cancelled],
            self::BillRequested => [self::Served, self::PartiallyPaid, self::Paid, self::Cancelled],
            self::PartiallyPaid => [self::PartiallyPaid, self::Paid, self::Cancelled],
            self::Paid => [self::Refunded],
            self::Cancelled, self::Refunded => [],
        };
    }

    public function canTransitionTo(self $to): bool
    {
        return in_array($to, $this->transitions(), true);
    }

    /** Adisyon hâlâ operasyonel olarak açık mı (masayı meşgul eder mi)? */
    public function isOpen(): bool
    {
        return ! in_array($this, [self::Paid, self::Cancelled, self::Refunded], true);
    }

    /** Kaleme dokunulabilir mi (ekle/çıkar/değiştir)? */
    public function allowsItemChanges(): bool
    {
        return ! in_array($this, [self::Paid, self::Cancelled, self::Refunded], true);
    }

    /** Mutfak-aşaması (kalemlerden türetilen) durumlar. */
    public function isKitchenPhase(): bool
    {
        return in_array($this, [
            self::Placed, self::SentToStation, self::Accepted, self::Preparing,
            self::PartiallyReady, self::Ready, self::AwaitingService, self::Served,
        ], true);
    }

    public function label(): string
    {
        return match ($this) {
            self::Draft => 'Taslak',
            self::PendingApproval => 'Onay bekliyor',
            self::Placed => 'Sipariş alındı',
            self::SentToStation => 'İstasyona gönderildi',
            self::Accepted => 'Kabul edildi',
            self::Preparing => 'Hazırlanıyor',
            self::PartiallyReady => 'Kısmen hazır',
            self::Ready => 'Hazır',
            self::AwaitingService => 'Servis bekliyor',
            self::Served => 'Servis edildi',
            self::BillRequested => 'Hesap istendi',
            self::PartiallyPaid => 'Kısmi ödendi',
            self::Paid => 'Ödendi',
            self::Cancelled => 'İptal',
            self::Refunded => 'İade',
        };
    }

    /** Tasarım sistemindeki AppIcon adı (renkten bağımsız ayırt edici). */
    public function icon(): string
    {
        return match ($this) {
            self::Draft => 'pencil',
            self::PendingApproval => 'bell',
            self::Placed => 'orders',
            self::SentToStation => 'arrow-right',
            self::Accepted => 'check',
            self::Preparing => 'chef-hat',
            self::PartiallyReady => 'chart',
            self::Ready => 'check-circle',
            self::AwaitingService => 'alert-circle',
            self::Served => 'utensils',
            self::BillRequested => 'cart',
            self::PartiallyPaid => 'chart',
            self::Paid => 'check-circle',
            self::Cancelled => 'x-circle',
            self::Refunded => 'arrow-left',
        };
    }

    /** BaseBadge renk varyantı. */
    public function variant(): string
    {
        return match ($this) {
            self::Draft => 'neutral',
            self::PendingApproval, self::Preparing, self::PartiallyReady,
            self::AwaitingService, self::BillRequested, self::PartiallyPaid => 'warning',
            self::Placed, self::SentToStation, self::Accepted, self::Served => 'info',
            self::Ready, self::Paid => 'success',
            self::Cancelled, self::Refunded => 'danger',
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
