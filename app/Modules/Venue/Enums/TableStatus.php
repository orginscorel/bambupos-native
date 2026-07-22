<?php

namespace App\Modules\Venue\Enums;

/**
 * Masa durumları (prompt §8.3). Sipariş modülü geldiğinde durum GEÇİŞLERİ
 * oraya bağlanır; bu enum durum kümesinin ve gösteriminin tek kaynağıdır.
 *
 * Erişilebilirlik: durum yalnız renkle anlatılmaz — her durumun ikonu ve
 * metni vardır (renk körlüğü desteği); arayüz üçünü birlikte gösterir.
 */
enum TableStatus: string
{
    case Available = 'available';
    case Occupied = 'occupied';
    case AwaitingOrder = 'awaiting_order';
    case OrderTaken = 'order_taken';
    case Preparing = 'preparing';
    case AwaitingService = 'awaiting_service';
    case Served = 'served';
    case BillRequested = 'bill_requested';
    case PartiallyPaid = 'partially_paid';
    case Paid = 'paid';
    case Cleaning = 'cleaning';
    case Reserved = 'reserved';
    case ReservationLate = 'reservation_late';
    case OutOfService = 'out_of_service';

    public function label(): string
    {
        return match ($this) {
            self::Available => 'Boş',
            self::Occupied => 'Oturuluyor',
            self::AwaitingOrder => 'Sipariş bekliyor',
            self::OrderTaken => 'Sipariş alındı',
            self::Preparing => 'Hazırlanıyor',
            self::AwaitingService => 'Servis bekliyor',
            self::Served => 'Servis edildi',
            self::BillRequested => 'Hesap istendi',
            self::PartiallyPaid => 'Kısmi ödendi',
            self::Paid => 'Ödendi',
            self::Cleaning => 'Temizleniyor',
            self::Reserved => 'Rezerve',
            self::ReservationLate => 'Rezervasyon gecikti',
            self::OutOfService => 'Kullanım dışı',
        };
    }

    /** Tasarım sistemindeki AppIcon adı (renkten bağımsız ayırt edici). */
    public function icon(): string
    {
        return match ($this) {
            self::Available => 'check-circle',
            self::Occupied => 'users',
            self::AwaitingOrder => 'bell',
            self::OrderTaken => 'orders',
            self::Preparing => 'chef-hat',
            self::AwaitingService => 'alert-circle',
            self::Served => 'utensils',
            self::BillRequested => 'cart',
            self::PartiallyPaid => 'chart',
            self::Paid => 'check',
            self::Cleaning => 'inbox',
            self::Reserved => 'user',
            self::ReservationLate => 'alert-triangle',
            self::OutOfService => 'x-circle',
        };
    }

    /** BaseBadge renk varyantı. */
    public function variant(): string
    {
        return match ($this) {
            self::Available => 'success',
            self::Occupied, self::OrderTaken, self::Served => 'info',
            self::AwaitingOrder, self::Preparing, self::AwaitingService,
            self::BillRequested, self::PartiallyPaid => 'warning',
            self::Paid => 'success',
            self::Cleaning => 'neutral',
            self::Reserved => 'primary',
            self::ReservationLate => 'danger',
            self::OutOfService => 'neutral',
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
