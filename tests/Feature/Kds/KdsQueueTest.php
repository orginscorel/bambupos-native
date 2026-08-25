<?php

namespace Tests\Feature\Kds;

use App\Modules\Catalog\Models\Allergen;
use App\Modules\Kds\Models\UserStation;

/**
 * KDS kuyruğu: kiracı izolasyonu · istasyon süzgeci · FİNANSAL SIZINTI YOK
 * (prompt §20) · alerjen uyarısı · cursor'lı polling (ADR-006).
 */
class KdsQueueTest extends KdsTestCase
{
    public function test_kuyruk_istasyon_suzgeciyle_calisir(): void
    {
        $setup = $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Kebap'],
            ['station' => 'bar', 'name' => 'Limonata'],
        ]);

        $kitchenUser = $this->makeUserInA(['kds.view']);
        $this->actingAs($kitchenUser);

        // Mutfak süzgeci: yalnız mutfak kalemi
        $res = $this->getJson('/api/v1/kds/queue?station=kitchen')->assertOk();
        $items = collect($res->json('orders.0.items'));
        $this->assertSame(['Kebap'], $items->pluck('name')->all());

        // Bar süzgeci: yalnız bar kalemi (bar ekranı = aynı altyapı)
        $res = $this->getJson('/api/v1/kds/queue?station=bar')->assertOk();
        $this->assertSame(['Limonata'], collect($res->json('orders.0.items'))->pluck('name')->all());

        // Süzgeçsiz: ikisi de
        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $this->assertCount(2, $res->json('orders.0.items'));
        $this->assertSame($setup['order_id'], $res->json('orders.0.id'));
    }

    public function test_istasyon_atamasi_olan_kullanici_yalniz_kendi_istasyonunu_gorur(): void
    {
        $this->createOrderWithItems([
            ['station' => 'kitchen', 'name' => 'Kebap'],
            ['station' => 'bar', 'name' => 'Limonata'],
        ]);

        $barUser = $this->makeUserInA(['kds.view']);
        $this->asTenant($this->a['tenant'], fn () => UserStation::query()->create([
            'user_id' => $barUser->id,
            'station_key' => 'bar',
        ]));

        $this->actingAs($barUser);

        // Süzgeçsiz istekte bile SUNUCU yalnız bar kalemini döndürür
        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $this->assertSame(['Limonata'], collect($res->json('orders.0.items'))->pluck('name')->all());

        // Başka istasyonun kuyruğu açıkça istenirse: 403
        $this->getJson('/api/v1/kds/queue?station=kitchen')->assertForbidden();

        // Başka istasyonun kalemi işaretlenemez
        $kitchenItemId = \App\Modules\Orders\Models\OrderItem::withoutTenancy()
            ->where('station', 'kitchen')->value('id');
        $this->postJson("/api/v1/kds/items/{$kitchenItemId}/status", ['to' => 'preparing'])->assertForbidden();
    }

    public function test_kiraci_izolasyonu_yabanci_siparis_gorunmez(): void
    {
        // Kiracı B kendi siparişini açar
        $b = $this->makeTenantWithUser();
        $this->actingAs($b['user']);
        $tableB = $this->makeTable($b);
        $productB = $this->makeProduct($b, ['station' => 'kitchen', 'name' => 'B-Yemek']);
        $orderB = $this->postJson('/api/v1/orders', [
            'branch_id' => $b['branch']->id, 'channel' => 'table', 'table_id' => $tableB->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderB}/items", ['product_id' => $productB->id, 'qty' => 1])->assertCreated();
        auth('web')->logout();

        // Kiracı A'nın mutfakçısı: B'nin siparişi LİSTEDE YOK
        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'A-Yemek']]);
        $this->actingAs($this->makeUserInA(['kds.view']));

        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $names = collect($res->json('orders'))->flatMap(fn ($o) => collect($o['items'])->pluck('name'));
        $this->assertTrue($names->contains('A-Yemek'));
        $this->assertFalse($names->contains('B-Yemek'));

        // B'nin kalemi id ile de işaretlenemez (scope → 404)
        $itemB = \App\Modules\Orders\Models\OrderItem::withoutTenancy()
            ->where('name', 'B-Yemek')->value('id');
        $this->postJson("/api/v1/kds/items/{$itemB}/status", ['to' => 'preparing'])->assertNotFound();
    }

    public function test_mutfak_ekraninda_finansal_alan_yoktur(): void
    {
        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $this->actingAs($this->makeUserInA(['kds.view']));

        $json = $this->getJson('/api/v1/kds/queue')->assertOk()->content();

        // Kuruş-integer şemasının TÜM para alanları `*_minor` (ADR-007) —
        // KDS yanıtında hiçbiri bulunamaz (prompt §20).
        $this->assertStringNotContainsString('_minor', $json);
        $this->assertStringNotContainsString('total', $json);
        $this->assertStringNotContainsString('price', $json);
        $this->assertStringNotContainsString('discount', $json);
    }

    public function test_alerjen_uyarisi_kuyrukta_gorunur(): void
    {
        $setup = $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Fıstıklı Tatlı']]);

        // Ürüne alerjen + diyet etiketi bağla
        $this->asTenant($this->a['tenant'], function (): void {
            $allergen = Allergen::query()->create([
                'kind' => 'allergen', 'code' => 'nuts', 'name' => 'Fıstık', 'sort_order' => 1,
            ]);
            $diet = Allergen::query()->create([
                'kind' => 'diet', 'code' => 'vegan', 'name' => 'Vegan', 'sort_order' => 2,
            ]);
            $product = \App\Modules\Catalog\Models\Product::query()->where('name', 'Fıstıklı Tatlı')->first();
            $product->allergens()->attach([$allergen->id, $diet->id]);
        });

        $this->actingAs($this->makeUserInA(['kds.view']));

        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $this->assertSame('Fıstık', $res->json('orders.0.items.0.allergens.0.name'));
        $this->assertSame($setup['order_id'], $res->json('orders.0.id'));

        // Diyet etiketi ALERJEN listesine KARIŞMAZ — ayrı alanda gider
        $this->assertCount(1, $res->json('orders.0.items.0.allergens'));
        $this->assertSame(['Vegan'], $res->json('orders.0.items.0.diets'));
    }

    public function test_polling_degisiklik_yoksa_204_bos_doner(): void
    {
        $this->createOrderWithItems([['station' => 'kitchen', 'name' => 'Kebap']]);
        $this->actingAs($this->makeUserInA(['kds.view']));

        $cursor = (int) $this->getJson('/api/v1/kds/queue')->json('cursor');
        $this->assertGreaterThan(0, $cursor);

        // Değişiklik yok → 204, gövde boş (sunucu tam kuyruk ÜRETMEZ)
        $res = $this->getJson("/api/v1/kds/updates?cursor={$cursor}");
        $res->assertNoContent();
        $this->assertSame((string) $cursor, $res->headers->get('X-Kds-Cursor'));

        // Bayat cursor → tam kuyruk + yeni cursor
        $res = $this->getJson('/api/v1/kds/updates?cursor=0')->assertOk();
        $this->assertSame($cursor, (int) $res->json('cursor'));
        $this->assertNotEmpty($res->json('orders'));
    }

    /**
     * Panel denetim notu (2026-08-06, "KDS şube-seçici"): Runner/Kitchen üst
     * çubuğundaki şube seçici eskiden `branch_id` sorgu parametresi
     * gönderiyordu ama bu uç onu HİÇ okumuyordu — dropdown sessizce hiçbir
     * şey değiştirmiyordu (yanlış şube gösterme riski). Düzeltme backend'e
     * DOKUNMADI: ekran artık gerçek `POST /api/v1/auth/active-branch`
     * ucuyla oturumdaki aktif şubeyi değiştiriyor. Bu test iki şeyi birden
     * kilitler: (1) `branch_id` sorgu parametresi HÂLÂ ve HER ZAMAN yok
     * sayılır (ŞUBE KAPSAMI istekten asla alınmaz), (2) gerçek aktif-şube
     * geçişi kuyruğu GERÇEKTEN değiştirir.
     */
    public function test_kuyruk_branch_id_parametresini_yok_sayar_yalniz_aktif_sube_gecisini_izler(): void
    {
        $branchB = $this->asTenant(
            $this->a['tenant'],
            fn () => \App\Modules\Tenancy\Models\Branch::factory()->create([
                'tenant_id' => $this->a['tenant']->id,
                'name' => 'B Şube',
            ])
        );

        $manager = $this->a['user']; // sahip = tüm izinler = yönetici (canSwitch)
        $this->actingAs($manager);

        // A şubesinde (varsayılan aktif) mutfak kalemi.
        $tableA = $this->makeTable($this->a);
        $productA = $this->makeProduct($this->a, ['station' => 'kitchen', 'name' => 'A-Yemek']);
        $orderA = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $tableA->id,
        ])->assertCreated()->json('order.id');
        $this->postJson("/api/v1/orders/{$orderA}/items", ['product_id' => $productA->id, 'qty' => 1])->assertCreated();
        $this->postJson("/api/v1/orders/{$orderA}/send-to-kitchen")->assertOk();

        // B'ye geç, B şubesinde de mutfak kalemi oluştur, sonra A'ya geri dön.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $branchB->id])->assertOk();
        $ctxB = ['tenant' => $this->a['tenant'], 'branch' => $branchB];
        $tableB = $this->makeTable($ctxB);
        $productB = $this->makeProduct($ctxB, ['station' => 'kitchen', 'name' => 'B-Yemek']);
        $orderB = $this->postJson('/api/v1/orders', [
            'branch_id' => $branchB->id, 'channel' => 'table', 'table_id' => $tableB->id,
        ])->assertCreated()->json('order.id');
        $this->postJson("/api/v1/orders/{$orderB}/items", ['product_id' => $productB->id, 'qty' => 1])->assertCreated();
        $this->postJson("/api/v1/orders/{$orderB}/send-to-kitchen")->assertOk();
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $this->a['branch']->id])->assertOk();

        $namesOf = fn ($res) => collect($res->json('orders'))
            ->flatMap(fn ($o) => collect($o['items'])->pluck('name'));

        // Aktif şube A: yalnız A'nın kalemi görünür.
        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $this->assertTrue($namesOf($res)->contains('A-Yemek'));
        $this->assertFalse($namesOf($res)->contains('B-Yemek'));

        // İstekte branch_id=B geçirilse BİLE (eski, kaldırılan davranış) —
        // sunucu bunu yok sayar, hâlâ A'nın kalemi döner. Bu satır regresyonu
        // (backend'in isteğe güvenmeye başlaması) yakalar.
        $res = $this->getJson("/api/v1/kds/queue?branch_id={$branchB->id}")->assertOk();
        $this->assertTrue($namesOf($res)->contains('A-Yemek'));
        $this->assertFalse($namesOf($res)->contains('B-Yemek'));

        // Gerçek geçiş: aktif şubeyi B yap → şimdi yalnız B'nin kalemi görünür.
        $this->postJson('/api/v1/auth/active-branch', ['branch_id' => $branchB->id])->assertOk();
        $res = $this->getJson('/api/v1/kds/queue')->assertOk();
        $this->assertTrue($namesOf($res)->contains('B-Yemek'));
        $this->assertFalse($namesOf($res)->contains('A-Yemek'));
    }
}
