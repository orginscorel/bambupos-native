<?php

namespace Tests\Feature\Orders;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * SATIŞ ANI SNAPSHOT'ı (prompt §25): ürün adı/fiyatı/KDV'si sonradan
 * değişse, hatta ürün SİLİNSE bile eski adisyon DEĞİŞMEZ.
 */
class OrderSnapshotTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    public function test_urun_fiyati_degisince_eski_adisyon_degismez(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Lahmacun', 'price_minor' => 12000, 'tax_rate' => 10.00]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 3])->assertCreated();

        // Fiyat + ad + KDV zammı
        $product->update(['price_minor' => 99900, 'name' => 'Lahmacun (ZAMLI)', 'tax_rate' => 20.00]);

        $order = $this->getJson("/api/v1/orders/{$orderId}")->json('order');
        $this->assertSame('Lahmacun', $order['items'][0]['name']);
        $this->assertSame(12000, $order['items'][0]['unit_price_minor']);
        $this->assertSame(10.0, (float) $order['items'][0]['tax_rate']);
        $this->assertSame(36000, $order['total_minor']);

        // Yeni adisyon YENİ fiyatı alır
        $order2 = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'package',
        ])->json('order.id');
        $res = $this->postJson("/api/v1/orders/{$order2}/items", ['product_id' => $product->id, 'qty' => 1]);
        $this->assertSame(99900, $res->json('order.items.0.unit_price_minor'));
    }

    public function test_urun_silinse_bile_adisyon_satiri_yasar(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Künefe', 'price_minor' => 15000]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 2]);

        $product->delete();

        $order = $this->getJson("/api/v1/orders/{$orderId}")->assertOk()->json('order');
        $this->assertSame('Künefe', $order['items'][0]['name']);
        $this->assertNull($order['items'][0]['product_id']); // referans koptu, snapshot duruyor
        $this->assertSame(30000, $order['total_minor']);
    }

    public function test_secenek_fiyati_degisince_eski_adisyon_degismez(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Burger', 'price_minor' => 20000]);
        $group = $this->attachOptionGroup($this->a, $product, ['name' => 'Ekstra'], [
            ['name' => 'Bacon', 'price_minor' => 3000],
        ]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $option = $group->options->first();
        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 1, 'option_ids' => [$option->id],
        ])->assertCreated();

        $option->update(['price_minor' => 9000, 'name' => 'Bacon (zamlı)']);

        $order = $this->getJson("/api/v1/orders/{$orderId}")->json('order');
        $this->assertSame(3000, $order['items'][0]['options'][0]['price_minor']);
        $this->assertSame('Bacon', $order['items'][0]['options'][0]['option_name']);
        $this->assertSame(23000, $order['total_minor']);
    }
}
