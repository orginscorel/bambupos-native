<?php

namespace Tests\Feature\Kds;

use App\Modules\Orders\Models\OrderItem;

/**
 * 409 çakışma senaryosu (prompt §12.4): bayat expected_version reddedilir,
 * ekran tazeleyip yeniden dener. Sürüm OrderService çekirdeğinde doğrulanır.
 */
class KdsConflictTest extends KdsTestCase
{
    public function test_bayat_surumle_kalem_isaretleme_409_doner(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        $this->actingAs($this->makeUserInA(['kds.view']));

        // Başka ekran siparişi değiştirdi (sürüm arttı)…
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'accepted'])->assertOk();

        // …bu ekran hâlâ ESKİ sürümü gönderiyor → 409, durum DEĞİŞMEZ
        $this->postJson("/api/v1/kds/items/{$itemId}/status", [
            'to' => 'ready',
            'expected_version' => $setup['version'],
        ])->assertStatus(409);

        $this->assertSame('accepted', OrderItem::withoutTenancy()->find($itemId)->status);

        // Güncel sürümle tekrar: başarılı
        $current = (int) \App\Modules\Orders\Models\Order::withoutTenancy()->find($setup['order_id'])->version;
        $this->postJson("/api/v1/kds/items/{$itemId}/status", [
            'to' => 'ready',
            'expected_version' => $current,
        ])->assertOk();
    }

    public function test_bayat_surumle_tumu_hazir_409_doner(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);

        $this->actingAs($this->makeUserInA(['kds.view']));

        // Sürümü artır
        $this->postJson("/api/v1/kds/items/{$setup['item_ids'][0]}/status", ['to' => 'preparing'])->assertOk();

        $this->postJson("/api/v1/kds/orders/{$setup['order_id']}/station-ready", [
            'station' => 'kitchen',
            'expected_version' => $setup['version'], // bayat
        ])->assertStatus(409);

        $this->assertSame('preparing', OrderItem::withoutTenancy()->find($setup['item_ids'][0])->status);
    }

    public function test_bayat_surumle_geri_alma_409_doner(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $itemId = $setup['item_ids'][0];

        $this->actingAs($this->makeUserInA(['kds.view']));
        $this->postJson("/api/v1/kds/items/{$itemId}/status", ['to' => 'ready'])->assertOk();

        $this->postJson("/api/v1/kds/items/{$itemId}/undo", [
            'expected_version' => $setup['version'], // bayat
        ])->assertStatus(409);

        $this->assertSame('ready', OrderItem::withoutTenancy()->find($itemId)->status);
    }
}
