<?php

namespace Tests\Feature\Notify;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Tenancy\Models\Branch;

/**
 * §8 Servis çağrısı bildirimi — masadan gelen garson/su/hesap çağrısı public
 * QR ucundan (ServiceRequestController) dispatch edilir; o ŞUBENİN garsonları
 * (orders.create) + KASA (payments.take, özellikle "hesap iste") + yönetici
 * in-app bildirim alır. MUTFAK almaz; başka şube personeli almaz; aynı masa+tür
 * kısa pencerede tek bildirim.
 */
class ServiceCallNotificationTest extends NotifyTestCase
{
    public function test_garson_kasa_ve_yonetici_bildirim_alir_mutfak_almaz(): void
    {
        $waiter = $this->makeUserInA(['orders.create', 'orders.view']);
        $cashier = $this->makeUserInA(['orders.view', 'payments.take']);
        $kitchen = $this->makeUserInA(['kds.view'], ['kitchen']);

        $table = $this->makeTable($this->a);

        $this->postJson('/api/v1/public/service-requests', [
            'token' => $table->qr_token, 'kind' => 'waiter',
        ])->assertCreated();

        // Garson bildirim aldı, gövdesi masa + tür.
        $waiterNotifs = $this->notificationsFor($waiter->id, NotificationType::ServiceCall->value);
        $this->assertCount(1, $waiterNotifs);
        $this->assertStringContainsString('Garson çağırıyor', (string) $waiterNotifs->first()->body);

        // Yönetici (sahip = a['user']) de alır.
        $this->assertCount(1, $this->notificationsFor($this->a['user']->id, NotificationType::ServiceCall->value));

        // KASA (payments.take) ARTIK alır — özellikle "hesap iste" kasaya ulaşsın.
        $this->assertCount(1, $this->notificationsFor($cashier->id, NotificationType::ServiceCall->value));

        // Mutfak (yalnız kds.view) almaz.
        $this->assertCount(0, $this->notificationsFor($kitchen->id, NotificationType::ServiceCall->value));
    }

    public function test_sube_izolasyonu_baska_sube_garsonu_almaz(): void
    {
        $branchB = Branch::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $otherBranchWaiter = $this->makeUserInA(['orders.create', 'orders.view'], [], $branchB->id);
        $sameBranchWaiter = $this->makeUserInA(['orders.create', 'orders.view']);

        $table = $this->makeTable($this->a); // a['branch']

        $this->postJson('/api/v1/public/service-requests', [
            'token' => $table->qr_token, 'kind' => 'water',
        ])->assertCreated();

        $this->assertCount(1, $this->notificationsFor($sameBranchWaiter->id, NotificationType::ServiceCall->value));
        $this->assertCount(0, $this->notificationsFor($otherBranchWaiter->id, NotificationType::ServiceCall->value));
    }

    public function test_ayni_masa_ve_tur_tek_bildirim_uretir(): void
    {
        $waiter = $this->makeUserInA(['orders.create', 'orders.view']);

        $table = $this->makeTable($this->a);

        // İlk çağrı → bildirim; 2 dk içinde aynı tür istek düzeyinde dedup edilir,
        // dispatch de kısa-pencere dedup ile ikinci bildirimi yazmaz.
        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])->assertCreated();
        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])->assertOk();

        $this->assertCount(1, $this->notificationsFor($waiter->id, NotificationType::ServiceCall->value));
    }

    public function test_ozellik_kapaliysa_bildirim_uretilmez(): void
    {
        $waiter = $this->makeUserInA(['orders.create', 'orders.view']);

        \App\Modules\Settings\Support\Features::set((int) $this->a['tenant']->id, 'service_calls', false);

        $table = $this->makeTable($this->a);

        $this->postJson('/api/v1/public/service-requests', ['token' => $table->qr_token, 'kind' => 'waiter'])
            ->assertStatus(403);

        $this->assertCount(0, $this->notificationsFor($waiter->id, NotificationType::ServiceCall->value));
    }

    /** Adisyon "ödemeye gönderilince" (request-bill) KASA "ödeme bekliyor" alır. */
    public function test_odemeye_gonderince_kasa_bildirim_alir(): void
    {
        $cashier = $this->makeUserInA(['orders.view', 'payments.take']);
        $order = $this->createOrderWithItems([['name' => 'Çay']]);

        // Yönetici (orders.update) adisyonu ödemeye gönderir.
        $this->actingAs($this->a['user']);
        $this->postJson("/api/v1/orders/{$order['order_id']}/request-bill", [
            'expected_version' => $order['version'],
        ])->assertOk();
        auth('web')->logout();

        $this->assertCount(1, $this->notificationsFor($cashier->id, NotificationType::AwaitingPayment->value));
    }
}
