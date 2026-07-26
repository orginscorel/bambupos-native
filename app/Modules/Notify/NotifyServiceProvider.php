<?php

namespace App\Modules\Notify;

use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Notify\Services\NotifyEmitter;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use Illuminate\Support\ServiceProvider;

/**
 * §8 Bildirim & Push modülü.
 *
 * OLAY BAĞLAMA — Orders/KDS modülleri Laravel event YAYINLAMAZ (tüm mutasyonlar
 * OrderService/KdsService + order_events). Inventory köprüsüyle AYNI desen:
 * ELOQUENT MODEL OLAYLARINDAN dinlenir (Orders koduna DOKUNULMAZ).
 *
 *  - OrderItem created                → order_placed  (mutfak/barista, kulvar)
 *  - OrderItem status → ready         → item_ready    (komi)
 *  - OrderItem status → served        → order_served  (yönetici, sessiz)
 *  - StockLevel qty kritik altına     → low_stock     (depo + yönetici)
 *  - Reservation status → no_show     → reservation_no_show
 *
 * "Yaklaşan rezervasyon" ve "komi teslim SLA" ZAMANA bağlı → cron
 * (notify:check-sla). Tüm dinleyiciler best-effort (NotifyEmitter yutar).
 */
class NotifyServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // Yeni sipariş kalemi kuyruğa düştü (mutfağa/baristaya haber).
        OrderItem::created(function (OrderItem $item): void {
            app(NotifyEmitter::class)->orderItemPlaced($item);
        });

        OrderItem::updated(function (OrderItem $item): void {
            if (! $item->wasChanged('status')) {
                return;
            }

            $status = (string) $item->status;

            if ($status === OrderItemStatus::Ready->value) {
                app(NotifyEmitter::class)->itemReady($item);
            } elseif ($status === OrderItemStatus::Served->value) {
                app(NotifyEmitter::class)->itemServed($item);
            }
        });

        // Düşük stok: anlık seviye kritik eşiğin ALTINA GEÇTİĞİNDE (bir kez).
        StockLevel::updated(function (StockLevel $level): void {
            if (! $level->wasChanged('qty_milli')) {
                return;
            }

            try {
                $critical = (int) ($level->item?->critical_qty_milli ?? 0);
                if ($critical <= 0) {
                    return;
                }

                $before = (int) $level->getOriginal('qty_milli');
                $after = (int) $level->qty_milli;

                // Yalnız eşiği YENİ geçiş (before >= critical > after) — tekrar tetiklemez.
                if ($before >= $critical && $after < $critical) {
                    app(NotifyEmitter::class)->lowStock($level);
                }
            } catch (\Throwable) {
                // yut — stok akışı bozulmaz
            }
        });

        // Rezervasyon no-show (durum geçişi anında; cron da tetikler).
        // NOT: Reservation.status enum'a CAST edilir → doğrudan enum karşılaştır.
        Reservation::updated(function (Reservation $reservation): void {
            if ($reservation->wasChanged('status')
                && $reservation->status === ReservationStatus::NoShow) {
                app(NotifyEmitter::class)->reservationNoShow($reservation);
            }
        });
    }
}
