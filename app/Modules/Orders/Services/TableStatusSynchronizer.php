<?php

namespace App\Modules\Orders\Services;

use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use App\Modules\Venue\Enums\TableStatus;

/**
 * Sipariş olayları → masa durumu (görev §3): Venue'nun bilinçli boş
 * bıraktığı geçiş kurallarını BURASI bağlar.
 *
 * Zincir: Boş → Oturuluyor → Sipariş alındı → Hazırlanıyor → Servis
 * bekliyor → Servis edildi → Hesap istendi → Kısmi ödendi → Ödendi →
 * Temizleniyor → Boş.
 *
 * Kurallar:
 *  - Masa durumu masadaki AÇIK siparişlerin en ileri aşamasından türetilir
 *    (bir masada birden çok adisyon olabilir: böl/ayrı hesap).
 *  - Açık sipariş kalmadıysa: son sipariş ödenmişse → Temizleniyor
 *    (oradan personel Boş'a alır), iptal edildiyse → Boş.
 *  - Reserved / OutOfService gibi operasyon-dışı durumlar sipariş yoksa
 *    EZİLMEZ (rezervasyonu sipariş kapanışı bozamaz).
 */
class TableStatusSynchronizer
{
    public function syncForOrder(Order $order, ?OrderStatus $justClosed = null): void
    {
        // sync() masadaki AÇIK siparişleri DB'den okur; çağıran servis
        // durumu henüz kaydetmemiş olabilir → önce kalıcılaştır.
        if ($order->isDirty()) {
            $order->save();
        }

        if ($order->table_id === null || ! $order->channelEnum()->usesTable()) {
            return;
        }

        $table = Table::withoutTenancy()->find($order->table_id);

        if ($table === null) {
            return;
        }

        $this->sync($table, $justClosed);
    }

    public function sync(Table $table, ?OrderStatus $justClosed = null): void
    {
        $openStatuses = Order::withoutTenancy()
            ->where('table_id', $table->id)
            ->whereNotIn('status', [OrderStatus::Paid->value, OrderStatus::Cancelled->value, OrderStatus::Refunded->value])
            ->pluck('status')
            ->map(fn (string $s): OrderStatus => OrderStatus::tryFrom($s) ?? OrderStatus::Placed);

        if ($openStatuses->isEmpty()) {
            $current = $table->status instanceof TableStatus ? $table->status : TableStatus::tryFrom((string) $table->status);

            // Rezervasyon / servis dışı: sipariş kapanışı ezmesin.
            if (in_array($current, [TableStatus::Reserved, TableStatus::ReservationLate, TableStatus::OutOfService], true)) {
                return;
            }

            $target = $justClosed === OrderStatus::Paid ? TableStatus::Cleaning : TableStatus::Available;
            $this->apply($table, $target);

            return;
        }

        // En İLERİ aşamadaki açık sipariş masayı tanımlar.
        $ranked = $openStatuses->sortByDesc(fn (OrderStatus $s): int => $this->rank($s))->first();

        $this->apply($table, $this->map($ranked));
    }

    private function apply(Table $table, TableStatus $status): void
    {
        if ($table->status instanceof TableStatus && $table->status === $status) {
            return;
        }

        $table->status = $status;
        $table->save();
    }

    private function map(OrderStatus $status): TableStatus
    {
        return match ($status) {
            OrderStatus::Draft => TableStatus::Occupied,
            OrderStatus::PendingApproval => TableStatus::AwaitingOrder,
            OrderStatus::Placed, OrderStatus::SentToStation, OrderStatus::Accepted => TableStatus::OrderTaken,
            OrderStatus::Preparing, OrderStatus::PartiallyReady => TableStatus::Preparing,
            OrderStatus::Ready, OrderStatus::AwaitingService => TableStatus::AwaitingService,
            OrderStatus::Served => TableStatus::Served,
            OrderStatus::BillRequested => TableStatus::BillRequested,
            OrderStatus::PartiallyPaid => TableStatus::PartiallyPaid,
            OrderStatus::Paid => TableStatus::Paid,
            OrderStatus::Cancelled, OrderStatus::Refunded => TableStatus::Available,
        };
    }

    /** Zincirdeki sıra (masa, en ileri aşamadaki adisyona göre gösterilir). */
    private function rank(OrderStatus $status): int
    {
        return match ($status) {
            OrderStatus::Draft => 0,
            OrderStatus::PendingApproval => 1,
            OrderStatus::Placed => 2,
            OrderStatus::SentToStation => 3,
            OrderStatus::Accepted => 4,
            OrderStatus::Preparing => 5,
            OrderStatus::PartiallyReady => 6,
            OrderStatus::Ready => 7,
            OrderStatus::AwaitingService => 8,
            OrderStatus::Served => 9,
            OrderStatus::BillRequested => 10,
            OrderStatus::PartiallyPaid => 11,
            OrderStatus::Paid, OrderStatus::Cancelled, OrderStatus::Refunded => -1,
        };
    }
}
