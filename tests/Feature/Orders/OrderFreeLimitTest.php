<?php

namespace Tests\Feature\Orders;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * free_limit ("N adet ücretsiz") fiyat kuralı: grup içinde seçilenler
 * fiyata göre büyükten küçüğe sıralanır, ilk N tanesi ÜCRETSİZ; kalanlar
 * kendi fiyatından ücretlendirilir. Kataloğun vaadi ile adisyon tutarı
 * çelişemez (Musteri-Menu bulgusu — yanlış tahsilat düzeltmesi).
 */
class OrderFreeLimitTest extends TestCase
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

    private function openOrder(): int
    {
        return $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $this->makeTable($this->a)->id,
        ])->json('order.id');
    }

    public function test_ucretsiz_adet_icinde_kalan_secenekler_ucretsizdir(): void
    {
        $product = $this->makeProduct($this->a, ['name' => 'Dürüm', 'price_minor' => 20000]);
        $group = $this->attachOptionGroup($this->a, $product, ['name' => 'Soslar', 'free_limit' => 2], [
            ['name' => 'Acı sos', 'price_minor' => 1000],
            ['name' => 'Sarımsaklı sos', 'price_minor' => 2000],
        ]);

        $orderId = $this->openOrder();

        // 2 sos ücretsiz vaadi → 2 seçim = 0 ek ücret
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 1,
            'option_ids' => $group->options->pluck('id')->all(),
        ])->assertCreated();

        $item = $res->json('order.items.0');
        $this->assertSame(0, $item['options_price_minor']);
        $this->assertSame(20000, $item['line_total_minor']);

        // Snapshot: her iki seçenek efektif 0 yazıldı
        $this->assertSame([0, 0], array_column($item['options'], 'price_minor'));
    }

    public function test_asan_secenekler_ucretlidir_en_pahalilar_bedava(): void
    {
        $product = $this->makeProduct($this->a, ['name' => 'Pizza', 'price_minor' => 30000]);
        $group = $this->attachOptionGroup($this->a, $product, ['name' => 'Ekstralar', 'free_limit' => 2], [
            ['name' => 'Mısır', 'price_minor' => 1000],
            ['name' => 'Peynir', 'price_minor' => 2000],
            ['name' => 'Sucuk', 'price_minor' => 3000],
        ]);

        $orderId = $this->openOrder();

        // 3 seçim, 2'si ücretsiz: en pahalı ikisi (3000+2000) bedava,
        // ücretlendirilen yalnız en ucuz (1000) — müşteri lehine.
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 2,
            'option_ids' => $group->options->pluck('id')->all(),
        ])->assertCreated();

        $item = $res->json('order.items.0');
        $this->assertSame(1000, $item['options_price_minor']);
        $this->assertSame(2 * (30000 + 1000), $item['line_total_minor']);

        // Snapshot'ta efektif fiyatlar: {Sucuk:0, Peynir:0, Mısır:1000}
        $prices = collect($item['options'])->pluck('price_minor', 'option_name')->all();
        $this->assertSame(0, $prices['Sucuk']);
        $this->assertSame(0, $prices['Peynir']);
        $this->assertSame(1000, $prices['Mısır']);
    }

    public function test_free_limit_sifir_ise_hepsi_ucretli(): void
    {
        $product = $this->makeProduct($this->a, ['name' => 'Burger', 'price_minor' => 25000]);
        $group = $this->attachOptionGroup($this->a, $product, ['name' => 'Ekstra', 'free_limit' => 0], [
            ['name' => 'Bacon', 'price_minor' => 3000],
        ]);

        $orderId = $this->openOrder();

        $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 1,
            'option_ids' => [$group->options->first()->id],
        ])->assertCreated();

        $this->assertSame(3000, $res->json('order.items.0.options_price_minor'));
        $this->assertSame(28000, $res->json('order.items.0.line_total_minor'));
    }
}
