<?php

namespace Tests\Feature\Notify;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\OrderService;

/**
 * §8 Alıcı yönlendirme + şube kapsamı + kişi tercihi (olay-tetikli).
 */
class NotificationDispatchTest extends NotifyTestCase
{
    public function test_yeni_siparis_kalemi_dogru_kulvara_gider(): void
    {
        $kitchen = $this->makeUserInA(['kds.view'], ['kitchen']);
        $barista = $this->makeUserInA(['kds.view'], ['barista']);
        $komi = $this->makeUserInA(['kds.deliver']);

        // Mutfak kalemi olan yeni sipariş → OrderItem::created olayı tetiklenir.
        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);

        // Mutfak personeli order_placed alır; barista (farklı kulvar) almaz.
        $this->assertCount(1, $this->notificationsFor($kitchen->id, NotificationType::OrderPlaced->value));
        $this->assertCount(0, $this->notificationsFor($barista->id, NotificationType::OrderPlaced->value));
        // Komi order_placed almaz (kds.view yok, hedef izin değil).
        $this->assertCount(0, $this->notificationsFor($komi->id, NotificationType::OrderPlaced->value));
    }

    public function test_barista_kalemi_mutfagi_rahatsiz_etmez(): void
    {
        $kitchen = $this->makeUserInA(['kds.view'], ['kitchen']);
        $barista = $this->makeUserInA(['kds.view'], ['barista']);

        $this->createOrderWithItems([['station' => 'bar', 'name' => 'Limonata']]);

        $this->assertCount(1, $this->notificationsFor($barista->id, NotificationType::OrderPlaced->value));
        $this->assertCount(0, $this->notificationsFor($kitchen->id, NotificationType::OrderPlaced->value));
    }

    public function test_ayni_siparise_ard_arda_kalem_kulvar_basina_tek_bildirim(): void
    {
        $kitchen = $this->makeUserInA(['kds.view'], ['kitchen']);

        // İki mutfak kalemi aynı siparişte → dedup (order_placed:{order}:kitchen).
        $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Kebap'],
            ['station' => 'kitchen', 'name' => 'Lahmacun'],
        ]);

        $this->assertCount(1, $this->notificationsFor($kitchen->id, NotificationType::OrderPlaced->value));
    }

    public function test_hazir_kalem_komiye_gider(): void
    {
        $komi = $this->makeUserInA(['kds.deliver']);

        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        // Kalemi HAZIR yap (OrderItem status → ready olayı item_ready tetikler).
        $this->markItemReady($itemId);

        $ready = $this->notificationsFor($komi->id, NotificationType::ItemReady->value);
        $this->assertCount(1, $ready);
        $this->assertStringContainsString('Kebap', (string) $ready->first()->title);
    }

    public function test_sube_izolasyonu_baska_sube_personeli_bildirim_almaz(): void
    {
        // Kiracı A'nın İKİNCİ şubesi + oradaki mutfak personeli.
        $branchB = \App\Modules\Tenancy\Models\Branch::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $otherBranchUser = $this->makeUserInA(['kds.view'], [], $branchB->id);
        $sameBranchUser = $this->makeUserInA(['kds.view'], ['kitchen']);

        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);

        $this->assertCount(1, $this->notificationsFor($sameBranchUser->id, NotificationType::OrderPlaced->value));
        $this->assertCount(0, $this->notificationsFor($otherBranchUser->id, NotificationType::OrderPlaced->value));
    }

    public function test_kisi_tercihi_kapaliysa_bildirim_yazilmaz(): void
    {
        $kitchen = $this->makeUserInA(['kds.view'], ['kitchen']);

        // Kullanıcı order_placed in-app'i KAPATIR.
        $this->actingAs($kitchen);
        $this->putJson('/api/v1/notifications/preferences', [
            'preferences' => [['type' => 'order_placed', 'in_app' => false, 'push' => false]],
        ])->assertOk();
        auth('web')->logout();

        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);

        $this->assertCount(0, $this->notificationsFor($kitchen->id, NotificationType::OrderPlaced->value));
    }

    /** Kalemi doğrudan servis çekirdeğinden HAZIR'a taşır (olay dinleyicisi tetiklenir). */
    private function markItemReady(int $itemId): void
    {
        $this->asTenant($this->a['tenant'], function () use ($itemId): void {
            $item = OrderItem::query()->findOrFail($itemId);
            app(OrderService::class)->setItemStatus($item->order, $item, OrderItemStatus::Ready, null, null);
        });
    }
}
