<?php

namespace App\Console\Commands;

use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Notify\Services\NotifyEmitter;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Console\Command;

/**
 * §8/§11 ZAMANA BAĞLI bildirim taraması (her dakika, schedule):
 *
 *  1. Komi teslim SLA ihlali: teslim ALINAN (kds_item_pickups) ama hâlâ 'ready'
 *     olan (masaya verilmemiş) kalem, pickup'tan bu yana SLA dk'yı aştıysa →
 *     komi + yönetici bildirimi (dedup: kalem başına bir kez).
 *  2. Yaklaşan onaylı rezervasyon: reserved_at lead penceresine girenler →
 *     garson/host + yönetici (dedup: rezervasyon başına bir kez).
 *
 * Kiracı-üstü tarama (runWithoutTenancy); bildirim kaydı tenant_id'yi olaydan
 * (Order/Reservation) alır. Tümü best-effort — dağıtım hatası cron'u düşürmez.
 */
class NotifyCheckSla extends Command
{
    protected $signature = 'notify:check-sla';

    protected $description = 'Komi teslim SLA ihlali + yaklaşan rezervasyon bildirimlerini tarar';

    public function handle(TenantContext $context, NotifyEmitter $emitter): int
    {
        $result = $context->runWithoutTenancy(function () use ($emitter): array {
            return [
                'sla' => $this->checkDeliverySla($emitter),
                'reservations' => $this->checkUpcomingReservations($emitter),
            ];
        });

        $this->info(sprintf(
            'Bildirim taraması: %d teslim SLA, %d yaklaşan rezervasyon.',
            $result['sla'],
            $result['reservations'],
        ));

        return self::SUCCESS;
    }

    private function checkDeliverySla(NotifyEmitter $emitter): int
    {
        $minutes = (int) config('notify.delivery_sla_minutes', 2);
        $threshold = now()->subMinutes($minutes);
        $count = 0;

        ItemPickup::query()
            ->where('created_at', '<=', $threshold)
            ->with(['user', 'orderItem.order.table'])
            ->chunkById(200, function ($pickups) use ($emitter, &$count): void {
                foreach ($pickups as $pickup) {
                    $item = $pickup->orderItem;

                    // Kalem hâlâ HAZIR = teslim alındı ama masaya götürülmedi.
                    if ($item === null || $item->statusEnum() !== OrderItemStatus::Ready) {
                        continue;
                    }

                    $emitter->deliverySlaBreach($item, $pickup);
                    $count++;
                }
            });

        return $count;
    }

    private function checkUpcomingReservations(NotifyEmitter $emitter): int
    {
        $lead = (int) config('notify.reservation_lead_minutes', 30);
        $count = 0;

        Reservation::query()
            ->where('status', ReservationStatus::Confirmed->value)
            ->whereBetween('reserved_at', [now(), now()->addMinutes($lead)])
            ->with('branch')
            ->chunkById(200, function ($reservations) use ($emitter, &$count): void {
                foreach ($reservations as $reservation) {
                    $emitter->reservationUpcoming($reservation);
                    $count++;
                }
            });

        return $count;
    }
}
