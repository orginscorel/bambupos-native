<?php

namespace App\Modules\Notify\Services;

use App\Modules\Inventory\Models\StockLevel;
use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Kds\Services\StationRegistry;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Reservations\Models\Reservation;

/**
 * §8 Domain → Bildirim köprüsü. Model olay dinleyicileri (NotifyServiceProvider)
 * ve SLA/rezervasyon cron'u BURAYI çağırır; alan verisinden (Order/OrderItem/
 * Reservation/StockLevel) başlık/gövde/derin-bağlantı üretip Dispatcher'a verir.
 *
 * Tümü best-effort (Dispatcher::notify zaten hataları yutar); okuma hataları da
 * sarmalanır → sipariş/stok akışı ASLA düşmez.
 */
class NotifyEmitter
{
    /** Uzun dedup penceresi (sn): "bir kez" olaylar (SLA/stok/rezervasyon). */
    private const ONCE_WINDOW = 86400;

    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
        private readonly StationRegistry $stations,
    ) {}

    /** Yeni sipariş kalemi kuyruğa düştü → o kalemin kulvarındaki mutfak/barista. */
    public function orderItemPlaced(OrderItem $item): void
    {
        try {
            $order = $item->order;
            if ($order === null || $order->tenant_id === null) {
                return;
            }

            $lane = $this->laneForStation($item->station);
            $dest = $this->orderDestination($order);
            $laneLabel = $lane === 'barista' ? 'Barista' : 'Mutfak';

            $this->dispatcher->notify(NotificationType::OrderPlaced, [
                'tenant_id' => (int) $order->tenant_id,
                'branch_id' => $order->branch_id !== null ? (int) $order->branch_id : null,
                'title' => 'Yeni sipariş · '.$dest,
                'body' => $laneLabel.' — yeni ürün geldi',
                'data' => ['order_id' => (int) $order->getKey(), 'url' => '/panel/siparisler'],
                'lane' => $lane,
                // Aynı siparişe hızlı ard arda kalem → kulvar başına TEK bildirim.
                'dedup_key' => 'order_placed:'.$order->getKey().':'.$lane,
            ]);
        } catch (\Throwable) {
            // yut — sipariş akışı bozulmaz
        }
    }

    /** Kalem HAZIR, teslim bekliyor → komiler. */
    public function itemReady(OrderItem $item): void
    {
        try {
            $order = $item->order;
            if ($order === null || $order->tenant_id === null) {
                return;
            }

            $dest = $this->orderDestination($order);

            $this->dispatcher->notify(NotificationType::ItemReady, [
                'tenant_id' => (int) $order->tenant_id,
                'branch_id' => $order->branch_id !== null ? (int) $order->branch_id : null,
                'title' => 'Hazır: '.$item->name,
                'body' => $item->name.' → '.$dest.' teslim bekliyor',
                'data' => [
                    'order_id' => (int) $order->getKey(),
                    'item_id' => (int) $item->getKey(),
                    'url' => '/panel/komi',
                ],
                'dedup_key' => 'item_ready:'.$item->getKey(),
            ]);
        } catch (\Throwable) {
            // yut
        }
    }

    /** Servis edildi → yönetici (varsayılan sessiz). */
    public function itemServed(OrderItem $item): void
    {
        try {
            $order = $item->order;
            if ($order === null || $order->tenant_id === null) {
                return;
            }

            $this->dispatcher->notify(NotificationType::OrderServed, [
                'tenant_id' => (int) $order->tenant_id,
                'branch_id' => $order->branch_id !== null ? (int) $order->branch_id : null,
                'title' => 'Servis edildi: '.$item->name,
                'body' => $this->orderDestination($order).' — '.$item->name,
                'data' => ['order_id' => (int) $order->getKey(), 'url' => '/panel/siparisler'],
                'dedup_key' => 'item_served:'.$item->getKey(),
            ]);
        } catch (\Throwable) {
            // yut
        }
    }

    /**
     * §11 Komi teslim SLA ihlali → teslim alan komi + yönetici.
     * SLA cron'undan çağrılır (kalem hâlâ ready ama pickup süresi aştı).
     */
    public function deliverySlaBreach(OrderItem $item, ItemPickup $pickup): void
    {
        try {
            $order = $item->order;
            if ($order === null || $order->tenant_id === null) {
                return;
            }

            $staff = $pickup->user?->name ?? 'Bir komi';
            $dest = $this->orderDestination($order);

            $this->dispatcher->notify(NotificationType::DeliverySlaBreach, [
                'tenant_id' => (int) $order->tenant_id,
                'branch_id' => $order->branch_id !== null ? (int) $order->branch_id : null,
                'title' => 'Teslim gecikmesi: '.$item->name,
                'body' => sprintf('%s, %s ürününü %s için teslim aldı ama masaya götürmedi.', $staff, $item->name, $dest),
                'data' => [
                    'order_id' => (int) $order->getKey(),
                    'item_id' => (int) $item->getKey(),
                    'staff' => $staff,
                    'url' => '/panel/komi',
                ],
                'extra_user_ids' => $pickup->user_id !== null ? [(int) $pickup->user_id] : [],
                'dedup_key' => 'sla:'.$item->getKey(),
                'dedup_window' => self::ONCE_WINDOW,
            ]);
        } catch (\Throwable) {
            // yut
        }
    }

    /** Kritik eşiğin altına düşen stok kalemi → depo yetkilisi + yönetici. */
    public function lowStock(StockLevel $level): void
    {
        try {
            $item = $level->item;
            $warehouse = $level->warehouse;
            if ($item === null || $level->tenant_id === null) {
                return;
            }

            $qty = number_format(((int) $level->qty_milli) / 1000, 2, ',', '.');
            $unit = $item->base_unit ?? '';
            $branchId = $warehouse?->branch_id !== null ? (int) $warehouse->branch_id : null;

            $this->dispatcher->notify(NotificationType::LowStock, [
                'tenant_id' => (int) $level->tenant_id,
                'branch_id' => $branchId,
                'title' => 'Düşük stok: '.$item->name,
                'body' => trim(sprintf('%s kritik eşiğin altında (%s %s%s).', $item->name, $qty, $unit,
                    $warehouse ? ' · '.$warehouse->name : '')),
                'data' => [
                    'item_id' => (int) $item->getKey(),
                    'warehouse_id' => $warehouse?->getKey(),
                    'url' => '/panel/stok',
                ],
                'dedup_key' => 'low_stock:'.$item->getKey().':'.($warehouse?->getKey() ?? '0'),
                'dedup_window' => self::ONCE_WINDOW,
            ]);
        } catch (\Throwable) {
            // yut
        }
    }

    /** Yaklaşan onaylı rezervasyon → garson/host + yönetici (cron). */
    public function reservationUpcoming(Reservation $reservation): void
    {
        $this->reservationNotify($reservation, NotificationType::ReservationUpcoming,
            'Yaklaşan rezervasyon', 'resv_up');
    }

    /** No-show → garson/host + yönetici (cron / durum geçişi). */
    public function reservationNoShow(Reservation $reservation): void
    {
        $this->reservationNotify($reservation, NotificationType::ReservationNoShow,
            'Rezervasyon gelmedi (no-show)', 'resv_ns');
    }

    private function reservationNotify(Reservation $reservation, NotificationType $type, string $title, string $keyPrefix): void
    {
        try {
            if ($reservation->tenant_id === null) {
                return;
            }

            $name = $reservation->customer_name ?: 'Misafir';
            $when = $reservation->reserved_at?->format('H:i') ?? '';
            $party = $reservation->party_size ? ' · '.$reservation->party_size.' kişi' : '';

            $this->dispatcher->notify($type, [
                'tenant_id' => (int) $reservation->tenant_id,
                'branch_id' => $reservation->branch_id !== null ? (int) $reservation->branch_id : null,
                'title' => $title.($when ? ' · '.$when : ''),
                'body' => trim($name.$party),
                'data' => ['reservation_id' => (int) $reservation->getKey(), 'url' => '/panel/rezervasyonlar'],
                'dedup_key' => $keyPrefix.':'.$reservation->getKey(),
                'dedup_window' => self::ONCE_WINDOW,
            ]);
        } catch (\Throwable) {
            // yut
        }
    }

    /* ---------------- yardımcılar ---------------- */

    private function laneForStation(?string $station): string
    {
        $barista = (array) config('authz.barista_stations', []);

        return in_array((string) $station, $barista, true) ? 'barista' : 'kitchen';
    }

    private function orderDestination(Order $order): string
    {
        $table = $order->table;
        if ($table !== null) {
            return $table->name ?: ('Masa '.$table->number);
        }

        return $order->customer_name ?: ('Sipariş #'.$order->getKey());
    }
}
