<?php

namespace Tests\Feature\Kds;

use App\Modules\Kds\Models\ItemPickup;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;

/**
 * KDS durum akışı: kalem ilerletme · sipariş durumunun kalemlerden
 * türetilmesi (bozulMAdığı) · tümü-hazır · geri alma · komi akışı ·
 * istasyon transferi.
 */
class KdsFlowTest extends KdsTestCase
{
    public function test_kalem_ilerletme_ve_kismen_hazir_turetmesi(): void
    {
        $setup = $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Kebap'],
            ['station' => 'bar', 'name' => 'Ayran'],
        ]);
        [$kebapId, $ayranId] = $setup['item_ids'];

        $this->actingAs($this->makeUserInA(['kds.view']));

        // Mutfak: kebap hazırlanıyor
        $this->postJson("/api/v1/kds/items/{$kebapId}/status", ['to' => 'preparing'])->assertOk();
        $this->assertSame('preparing', Order::withoutTenancy()->find($setup['order_id'])->status);

        // Bar: ayran hazır → sipariş "Kısmen hazır" (türetme BOZULMADI)
        $this->postJson("/api/v1/kds/items/{$ayranId}/status", ['to' => 'ready'])->assertOk();
        $this->assertSame('partially_ready', Order::withoutTenancy()->find($setup['order_id'])->status);

        // Kebap da hazır → sipariş "Hazır"
        $this->postJson("/api/v1/kds/items/{$kebapId}/status", ['to' => 'ready'])->assertOk();
        $this->assertSame('ready', Order::withoutTenancy()->find($setup['order_id'])->status);

        // Geriye gidiş KDS ilerletme ucundan REDDEDİLİR (yalnız-ileri korunur)
        $this->postJson("/api/v1/kds/items/{$kebapId}/status", ['to' => 'preparing'])->assertUnprocessable();
    }

    public function test_istasyonun_tum_kalemleri_tek_dokunusla_hazir(): void
    {
        $setup = $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Kebap'],
            ['station' => 'kitchen', 'name' => 'Pide'],
            ['station' => 'bar', 'name' => 'Ayran'],
        ]);

        $this->actingAs($this->makeUserInA(['kds.view']));

        $this->postJson("/api/v1/kds/orders/{$setup['order_id']}/station-ready", [
            'station' => 'kitchen',
            'expected_version' => $setup['version'],
        ])->assertOk();

        $statuses = OrderItem::withoutTenancy()
            ->where('order_id', $setup['order_id'])
            ->pluck('status', 'name');

        $this->assertSame('ready', $statuses['Kebap']);
        $this->assertSame('ready', $statuses['Pide']);
        $this->assertSame('placed', $statuses['Ayran']); // bar kalemine DOKUNULMADI

        $this->assertSame('partially_ready', Order::withoutTenancy()->find($setup['order_id'])->status);
    }

    public function test_yanlis_hazir_isareti_geri_alinir_ve_durum_yeniden_turetilir(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        $this->actingAs($this->makeUserInA(['kds.view']));

        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'ready'])->assertOk();
        $this->assertSame('ready', Order::withoutTenancy()->find($setup['order_id'])->status);

        // GERİ AL: ready → preparing; sipariş durumu yeniden türetilir
        $res = $this->postJson("/api/v1/kds/items/{$itemId}/undo")->assertOk();
        $this->assertSame('preparing', $res->json('item.status'));
        $this->assertSame('preparing', Order::withoutTenancy()->find($setup['order_id'])->status);

        // İz: order_events'e düştü
        $this->assertDatabaseHas('order_events', [
            'order_id' => $setup['order_id'],
            'type' => 'kds_status_undone',
            'from_status' => 'ready',
            'to_status' => 'preparing',
        ]);

        // Hazır olmayan kalem geri alınamaz
        $this->postJson("/api/v1/kds/items/{$itemId}/undo")->assertUnprocessable();
    }

    public function test_komi_akisi_teslim_aldim_ve_masaya_goturdum(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        // Mutfak hazırlar
        $this->actingAs($this->makeUserInA(['kds.view']));
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'ready'])->assertOk();
        auth('web')->logout();

        // Komi: hazır listesinde görür
        $komi = $this->makeUserInA(['kds.deliver']);
        $this->actingAs($komi);

        $res = $this->getJson('/api/v1/kds/queue?mode=runner')->assertOk();
        $this->assertSame('Kebap', $res->json('items.0.name'));
        $this->assertNull($res->json('items.0.picked_up_at'));

        // Hazır olmadan teslim alınamaz kuralı: önce teslim al (item hazır)
        $this->postJson("/api/v1/kds/items/{$itemId}/pickup")->assertCreated();
        $this->assertSame(1, ItemPickup::withoutTenancy()->where('order_item_id', $itemId)->count());

        // Teslim işareti listede görünür
        $res = $this->getJson('/api/v1/kds/queue?mode=runner')->assertOk();
        $this->assertNotNull($res->json('items.0.picked_up_at'));

        // Teslim işaretini geri al
        $this->deleteJson("/api/v1/kds/items/{$itemId}/pickup")->assertOk();
        $this->assertSame(0, ItemPickup::withoutTenancy()->where('order_item_id', $itemId)->count());

        // Masaya götürdüm = served; sipariş "Servis edildi"ye türetilir
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'served'])->assertOk();
        $this->assertSame('served', Order::withoutTenancy()->find($setup['order_id'])->status);

        // Komi yanlış işaretledi: served → ready geri alınabilir
        $this->postJson("/api/v1/kds/items/{$itemId}/undo")->assertOk();
        $this->assertSame('ready', OrderItem::withoutTenancy()->find($itemId)->status);
        $this->assertSame('ready', Order::withoutTenancy()->find($setup['order_id'])->status);
    }

    public function test_hazir_olmayan_kalem_teslim_alinamaz(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);

        $this->actingAs($this->makeUserInA(['kds.deliver']));
        $this->postJson("/api/v1/kds/items/{$setup['item_ids'][0]}/pickup")->assertUnprocessable();
    }

    public function test_istasyon_transferi(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Sütlaç']]);
        $itemId = $setup['item_ids'][0];

        $this->actingAs($this->makeUserInA(['kds.view']));

        // Geçersiz istasyona transfer reddedilir
        $this->postJson("/api/v1/kds/items/{$itemId}/transfer", ['station' => 'olmayan'])->assertUnprocessable();

        // Tatlı istasyonuna transfer
        $res = $this->postJson("/api/v1/kds/items/{$itemId}/transfer", [
            'station' => 'dessert',
            'expected_version' => $setup['version'],
        ])->assertOk();
        $this->assertSame('dessert', $res->json('item.station'));

        // İz: order_events'te from/to istasyon
        $this->assertDatabaseHas('order_events', [
            'order_id' => $setup['order_id'],
            'type' => 'kds_station_transferred',
        ]);

        // Artık mutfak süzgecinde görünmez, tatlıda görünür
        $this->assertEmpty($this->getJson('/api/v1/kds/queue?station=kitchen')->json('orders'));
        $this->assertSame('Sütlaç', $this->getJson('/api/v1/kds/queue?station=dessert')->json('orders.0.items.0.name'));

        // Hazır kalem transfer edilemez
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'ready'])->assertOk();
        $this->postJson("/api/v1/kds/items/{$itemId}/transfer", ['station' => 'kitchen'])->assertUnprocessable();
    }
}
