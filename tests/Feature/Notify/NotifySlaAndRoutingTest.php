<?php

namespace Tests\Feature\Notify;

use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\OrderService;

/**
 * §8/§11 Komi teslim SLA cron'u + alıcı yönlendirme (izin/yönetici bazlı).
 */
class NotifySlaAndRoutingTest extends NotifyTestCase
{
    public function test_teslim_sla_ihlali_komi_ve_yoneticiye_gider(): void
    {
        $komi = $this->makeUserInA(['kds.deliver']);

        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        // Kalem HAZIR + komi TESLİM ALDI ama süresinde vermedi (pickup eski).
        $this->asTenant($this->a['tenant'], function () use ($itemId, $komi): void {
            $item = OrderItem::query()->findOrFail($itemId);
            app(OrderService::class)->setItemStatus($item->order, $item, OrderItemStatus::Ready, null, null);

            $pickup = ItemPickup::query()->create(['order_item_id' => $itemId, 'user_id' => $komi->id]);
            // SLA eşiğini aşacak şekilde geçmişe çek.
            $pickup->forceFill(['created_at' => now()->subMinutes(10)])->saveQuietly();
        });

        $this->artisan('notify:check-sla')->assertSuccessful();

        // Teslim alan komi + yönetici (sahip) SLA bildirimi alır.
        $this->assertCount(1, $this->notificationsFor($komi->id, NotificationType::DeliverySlaBreach->value));
        $this->assertCount(1, $this->notificationsFor($this->a['user']->id, NotificationType::DeliverySlaBreach->value));
    }

    public function test_sla_ihlali_bir_kez_uretilir(): void
    {
        $komi = $this->makeUserInA(['kds.deliver']);
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        $this->asTenant($this->a['tenant'], function () use ($itemId, $komi): void {
            $item = OrderItem::query()->findOrFail($itemId);
            app(OrderService::class)->setItemStatus($item->order, $item, OrderItemStatus::Ready, null, null);
            $pickup = ItemPickup::query()->create(['order_item_id' => $itemId, 'user_id' => $komi->id]);
            $pickup->forceFill(['created_at' => now()->subMinutes(10)])->saveQuietly();
        });

        $this->artisan('notify:check-sla')->assertSuccessful();
        $this->artisan('notify:check-sla')->assertSuccessful(); // ikinci tur

        // Uzun-pencere dedup: tekrar tetiklenmez.
        $this->assertCount(1, $this->notificationsFor($komi->id, NotificationType::DeliverySlaBreach->value));
    }

    public function test_dusuk_stok_yonlendirmesi_depo_yetkilisi_ve_yonetici(): void
    {
        $stockUser = $this->makeUserInA(['stock.adjust']);
        $kdsUser = $this->makeUserInA(['kds.view']);

        // Dispatcher'ı doğrudan çağır (inventory model akışını kurmadan yönlendirmeyi test et).
        app(NotificationDispatcher::class)->notify(NotificationType::LowStock, [
            'tenant_id' => (int) $this->a['tenant']->id,
            'branch_id' => (int) $this->a['branch']->id,
            'title' => 'Düşük stok: Domates',
            'body' => 'kritik eşiğin altında',
            'data' => ['url' => '/panel/stok'],
            'dedup_key' => 'low_stock:1:1',
        ]);

        $this->assertCount(1, $this->notificationsFor($stockUser->id, NotificationType::LowStock->value));
        // Yönetici (sahip) de alır.
        $this->assertCount(1, $this->notificationsFor($this->a['user']->id, NotificationType::LowStock->value));
        // KDS personeli (stok/yönetici değil) almaz.
        $this->assertCount(0, $this->notificationsFor($kdsUser->id, NotificationType::LowStock->value));
    }
}
