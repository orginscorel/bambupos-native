<?php

declare(strict_types=1);

namespace App\Modules\Delivery\Services;

use App\Modules\Delivery\Models\OrderDelivery;
use App\Modules\Identity\Models\User;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\Orders\Models\Order;

/**
 * TESLİMAT iş kuralları: teslimat kaydı üretimi, kurye atama, durum geçişi
 * ve API sunumu (DTO).
 *
 * Teslimat kaydı BİRİNCİLDİR: bildirim (DeliveryAssigned / DeliveryDelivered)
 * yalnızca best-effort ek adımdır; hata olsa da kayıt başarılı sayılır
 * (try/catch ile yutulur). tenant_id BelongsToTenant ile bağlamdan atanır.
 */
class DeliveryService
{
    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
    ) {
    }

    /**
     * Siparişin teslimat kaydını getir; yoksa üret (firstOrCreate). Paket
     * sipariş açılınca teslimat kaydı ilk erişimde oluşturulur; adres
     * mevcutsa sipariş notundan alınır, yoksa boş bırakılır (yönetici düzenler).
     */
    public function forOrder(Order $order): OrderDelivery
    {
        return OrderDelivery::firstOrCreate(
            ['order_id' => (int) $order->getKey()],
            [
                'branch_id' => $order->branch_id !== null ? (int) $order->branch_id : null,
                'address' => (string) ($order->note ?? ''),
                'status' => 'pending',
                'fee_minor' => 0,
            ],
        );
    }

    /**
     * Kuryeyi ata (status=assigned, assigned_at=now). Kaydeder, sonra atanan
     * kuryeye DeliveryAssigned bildirimi gönderir (best-effort).
     */
    public function assign(OrderDelivery $delivery, int $courierId, User $actor): OrderDelivery
    {
        $delivery->courier_id = $courierId;
        $delivery->status = 'assigned';
        $delivery->assigned_at = now();
        $delivery->save();

        $this->notifyAssigned($delivery, $courierId);

        return $delivery;
    }

    /**
     * Durum güncelle. delivered → delivered_at damgalanır ve yöneticilere
     * DeliveryDelivered bildirimi gider (best-effort). delivered'dan çıkılırsa
     * (yönetici düzeltmesi) damga temizlenir.
     */
    public function setStatus(OrderDelivery $delivery, string $status): OrderDelivery
    {
        $delivery->status = $status;

        if ($status === 'delivered') {
            // delivered'a İLK geçişte damgala; zaten delivered ise özgün zamanı KORU.
            $delivery->delivered_at = $delivery->delivered_at ?? now();
        } else {
            $delivery->delivered_at = null;
        }

        $delivery->save();

        if ($status === 'delivered') {
            $this->notifyDelivered($delivery);
        }

        return $delivery;
    }

    /**
     * API sunumu (DeliveryDTO). Tarihler ISO-8601; sipariş ve kurye iç içe nesne.
     *
     * @return array<string, mixed>
     */
    public function toDto(OrderDelivery $delivery): array
    {
        $order = $delivery->order;
        $courier = $delivery->courier;

        return [
            'id' => (int) $delivery->getKey(),
            'order_id' => (int) $delivery->order_id,
            'order' => $order !== null ? [
                'id' => (int) $order->getKey(),
                'number' => (int) $order->getKey(),
                'customer_name' => $order->customer_name,
                'customer_phone' => $order->customer_phone,
                'total_minor' => (int) $order->total_minor,
                'service_type' => (string) $order->service_type,
            ] : null,
            'address' => $delivery->address,
            'note' => $delivery->note,
            'status' => $delivery->status,
            'status_label' => $delivery->statusLabel(),
            'fee_minor' => (int) $delivery->fee_minor,
            'courier' => $courier !== null ? [
                'id' => (int) $courier->getKey(),
                'name' => $courier->name,
            ] : null,
            'assigned_at' => $delivery->assigned_at?->toIso8601String(),
            'delivered_at' => $delivery->delivered_at?->toIso8601String(),
            'created_at' => $delivery->created_at?->toIso8601String(),
        ];
    }

    /* ---------------- Bildirimler (best-effort) ---------------- */

    /** Atama bildirimi — YALNIZ atanan kurye (extra_user_ids). */
    private function notifyAssigned(OrderDelivery $delivery, int $courierId): void
    {
        try {
            if ($delivery->tenant_id === null) {
                return;
            }

            $order = $delivery->order;
            $who = $order?->customer_name ?: ('Sipariş #'.$delivery->order_id);

            $this->dispatcher->notify(NotificationType::DeliveryAssigned, [
                'tenant_id' => (int) $delivery->tenant_id,
                'branch_id' => $delivery->branch_id !== null ? (int) $delivery->branch_id : null,
                'title' => 'Yeni teslimat: '.$who,
                'body' => $delivery->address !== '' ? $delivery->address : 'Sana bir paket teslimatı atandı.',
                'data' => [
                    'delivery_id' => (int) $delivery->getKey(),
                    'order_id' => (int) $delivery->order_id,
                    'url' => '/teslimatlarim',
                ],
                // DeliveryAssigned targetPermissions=[] + includeManagers=false →
                // YALNIZ atanan kurye (extra_user_ids) bildirim alır.
                'extra_user_ids' => [$courierId],
                'dedup_key' => 'delivery_assigned:'.$delivery->getKey(),
            ]);
        } catch (\Throwable) {
            // yut — teslimat kaydı bildirimsiz de başarılı olsun
        }
    }

    /** Teslim tamamlandı bildirimi — teslimat panosunu görenler + yönetici. */
    private function notifyDelivered(OrderDelivery $delivery): void
    {
        try {
            if ($delivery->tenant_id === null) {
                return;
            }

            $order = $delivery->order;
            $who = $order?->customer_name ?: ('Sipariş #'.$delivery->order_id);
            $courier = $delivery->courier?->name ?? 'Kurye';

            $this->dispatcher->notify(NotificationType::DeliveryDelivered, [
                'tenant_id' => (int) $delivery->tenant_id,
                'branch_id' => $delivery->branch_id !== null ? (int) $delivery->branch_id : null,
                'title' => 'Teslim edildi: '.$who,
                'body' => $courier.' teslimatı tamamladı.',
                'data' => [
                    'delivery_id' => (int) $delivery->getKey(),
                    'order_id' => (int) $delivery->order_id,
                    'url' => '/panel/teslimat',
                ],
                'dedup_key' => 'delivery_delivered:'.$delivery->getKey(),
            ]);
        } catch (\Throwable) {
            // yut
        }
    }
}
