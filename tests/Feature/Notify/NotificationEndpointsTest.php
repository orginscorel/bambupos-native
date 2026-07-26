<?php

namespace Tests\Feature\Notify;

use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Models\Notification;
use App\Modules\Notify\Models\NotificationPreference;
use App\Modules\Notify\Models\PushSubscription;

/**
 * §8 Panel zili + push abonelik + tercih uçları (HTTP).
 */
class NotificationEndpointsTest extends NotifyTestCase
{
    public function test_zil_listesi_okunmamis_sayisiyla_doner(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->seedNotification($user->id, 'order_placed', read: false);
        $this->seedNotification($user->id, 'item_ready', read: true);

        $this->actingAs($user);
        $res = $this->getJson('/api/v1/notifications')->assertOk();

        $this->assertSame(1, $res->json('unread_count'));
        $this->assertCount(2, $res->json('items'));
    }

    public function test_tek_bildirim_okundu_isaretlenir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $n = $this->seedNotification($user->id, 'order_placed', read: false);

        $this->actingAs($user);
        $this->postJson("/api/v1/notifications/{$n->id}/read")->assertOk();

        $this->assertNotNull(Notification::withoutTenancy()->find($n->id)->read_at);
    }

    public function test_baskasinin_bildirimi_okundu_isaretlenemez(): void
    {
        $owner = $this->makeUserInA(['kds.view']);
        $other = $this->makeUserInA(['kds.view']);
        $n = $this->seedNotification($owner->id, 'order_placed', read: false);

        $this->actingAs($other);
        $this->postJson("/api/v1/notifications/{$n->id}/read")->assertNotFound();
    }

    public function test_hepsi_okundu_isaretlenir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->seedNotification($user->id, 'order_placed', read: false);
        $this->seedNotification($user->id, 'item_ready', read: false);

        $this->actingAs($user);
        $this->postJson('/api/v1/notifications/read-all')->assertOk();

        $this->assertSame(0, Notification::withoutTenancy()->where('user_id', $user->id)->whereNull('read_at')->count());
    }

    public function test_push_abonelik_kaydedilir_ve_silinir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->actingAs($user);

        $endpoint = 'https://fcm.googleapis.com/fcm/send/abc123';
        $this->postJson('/api/v1/push/subscribe', [
            'endpoint' => $endpoint,
            'keys' => ['p256dh' => 'BPk_key', 'auth' => 'auth_token'],
        ])->assertOk();

        $this->assertSame(1, PushSubscription::withoutTenancy()->where('user_id', $user->id)->count());

        // Aynı endpoint tekrar → upsert (tek satır kalır).
        $this->postJson('/api/v1/push/subscribe', [
            'endpoint' => $endpoint,
            'keys' => ['p256dh' => 'BPk_key2', 'auth' => 'auth_token2'],
        ])->assertOk();
        $this->assertSame(1, PushSubscription::withoutTenancy()->where('user_id', $user->id)->count());

        $this->postJson('/api/v1/push/unsubscribe', ['endpoint' => $endpoint])->assertOk();
        $this->assertSame(0, PushSubscription::withoutTenancy()->where('user_id', $user->id)->count());
    }

    public function test_tercih_katalogu_ve_guncelleme(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->actingAs($user);

        $res = $this->getJson('/api/v1/notifications/preferences')->assertOk();
        $this->assertNotEmpty($res->json('types'));

        $this->putJson('/api/v1/notifications/preferences', [
            'preferences' => [['type' => 'order_placed', 'in_app' => false, 'push' => true]],
        ])->assertOk();

        $pref = NotificationPreference::withoutTenancy()
            ->where('user_id', $user->id)->where('type', 'order_placed')->first();
        $this->assertNotNull($pref);
        $this->assertFalse((bool) $pref->in_app);
        $this->assertTrue((bool) $pref->push);
    }

    public function test_gecersiz_tip_reddedilir(): void
    {
        $user = $this->makeUserInA(['kds.view']);
        $this->actingAs($user);

        $this->putJson('/api/v1/notifications/preferences', [
            'preferences' => [['type' => 'uydurma_tip', 'in_app' => true, 'push' => true]],
        ])->assertStatus(422);
    }

    private function seedNotification(int $userId, string $type, bool $read): Notification
    {
        return $this->asTenant($this->a['tenant'], fn (): Notification => Notification::query()->create([
            'branch_id' => $this->a['branch']->id,
            'user_id' => $userId,
            'type' => $type,
            'title' => NotificationType::from($type)->label(),
            'body' => 'test',
            'read_at' => $read ? now() : null,
        ]));
    }
}
