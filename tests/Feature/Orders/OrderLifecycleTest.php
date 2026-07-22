<?php

namespace Tests\Feature\Orders;

use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Adisyon yaşam döngüsü: açma, kalem ekleme (snapshot + seçenek), durum
 * makinesi (geçerli/geçersiz geçişler), kalem-durumlarından türetme,
 * hesap isteme, kısmi/tam ödeme ve MASA DURUMU SENKRONU (görev §2–§3).
 */
class OrderLifecycleTest extends TestCase
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

    public function test_masa_adisyonu_tam_akis_ve_masa_durumu_senkronu(): void
    {
        $table = $this->makeTable($this->a);
        $cola = $this->makeProduct($this->a, ['name' => 'Kola', 'price_minor' => 5000, 'tax_rate' => 20.00]);
        $kebap = $this->makeProduct($this->a, ['name' => 'Adana Kebap', 'price_minor' => 30000, 'tax_rate' => 10.00]);

        // 1) Masa aç → sipariş alındı, masa "Sipariş alındı"
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id,
            'channel' => 'table',
            'table_id' => $table->id,
            'guest_count' => 2,
        ])->assertCreated()->json('order.id');

        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);

        // 2) Kalemler
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $cola->id, 'qty' => 2])->assertCreated();
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $kebap->id, 'qty' => 1])->assertCreated();

        $this->assertSame(2 * 5000 + 30000, $res->json('order.items_total_minor'));
        $this->assertSame(40000, $res->json('order.total_minor'));

        $items = collect($res->json('order.items'));
        $colaItem = $items->firstWhere('name', 'Kola');
        $kebapItem = $items->firstWhere('name', 'Adana Kebap');

        // 3) Kalem durumları AYRI akar: içecek servis edildi, yemek hazırlanıyor
        $this->putJson("/api/v1/orders/{$orderId}/items/{$colaItem['id']}/status", ['status' => 'served'])->assertOk();
        $res = $this->putJson("/api/v1/orders/{$orderId}/items/{$kebapItem['id']}/status", ['status' => 'preparing'])->assertOk();

        // Türetilen sipariş durumu: kısmen hazır (biri servis edildi, biri değil)
        $this->assertSame('partially_ready', $res->json('order.status'));
        $this->assertSame('preparing', Table::withoutTenancy()->find($table->id)->status->value);

        // 4) Yemek hazır → sipariş "Hazır", masa "Servis bekliyor"
        $res = $this->putJson("/api/v1/orders/{$orderId}/items/{$kebapItem['id']}/status", ['status' => 'ready'])->assertOk();
        $this->assertSame('ready', $res->json('order.status'));
        $this->assertSame('awaiting_service', Table::withoutTenancy()->find($table->id)->status->value);

        // 5) Servis → masa "Servis edildi"
        $res = $this->putJson("/api/v1/orders/{$orderId}/items/{$kebapItem['id']}/status", ['status' => 'served'])->assertOk();
        $this->assertSame('served', $res->json('order.status'));
        $this->assertSame('served', Table::withoutTenancy()->find($table->id)->status->value);

        // 6) Hesap iste → masa "Hesap istendi"
        $this->postJson("/api/v1/orders/{$orderId}/request-bill")->assertOk();
        $this->assertSame('bill_requested', Table::withoutTenancy()->find($table->id)->status->value);

        // 7) Kısmi ödeme → "Kısmi ödendi"
        $res = $this->postJson("/api/v1/orders/{$orderId}/pay", ['amount_minor' => 15000, 'method' => 'cash'])->assertOk();
        $this->assertSame('partially_paid', $res->json('order.status'));
        $this->assertSame('partially_paid', Table::withoutTenancy()->find($table->id)->status->value);

        // 8) Kalan ödeme → "Ödendi", masa "Temizleniyor" (açık adisyon kalmadı)
        $res = $this->postJson("/api/v1/orders/{$orderId}/pay", ['amount_minor' => 25000, 'method' => 'card'])->assertOk();
        $this->assertSame('paid', $res->json('order.status'));
        $this->assertSame(0, $res->json('order.remaining_minor'));
        $this->assertSame('cleaning', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_gecersiz_durum_gecisleri_reddedilir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])->assertCreated();

        // Sipariş alındı → doğrudan "İade" durumuna geçilemez (ayrı uç + guard)
        $this->putJson("/api/v1/orders/{$orderId}/status", ['status' => 'refunded'])->assertUnprocessable();

        // Ödenmemiş sipariş iade edilemez
        $this->postJson("/api/v1/orders/{$orderId}/refund", ['reason' => 'test iade'])->assertUnprocessable();

        // placed → paid durum ucuyla atlanamaz (yalnız ödeme ucuyla)
        $this->putJson("/api/v1/orders/{$orderId}/status", ['status' => 'paid'])->assertUnprocessable();

        // Kalem: servis edilen kalem tekrar "hazırlanıyor" yapılamaz (yalnız ileri)
        $itemId = $this->getJson("/api/v1/orders/{$orderId}")->json('order.items.0.id');
        $this->putJson("/api/v1/orders/{$orderId}/items/{$itemId}/status", ['status' => 'served'])->assertOk();
        $this->putJson("/api/v1/orders/{$orderId}/items/{$itemId}/status", ['status' => 'preparing'])->assertUnprocessable();

        // İptal edilen sipariş üstünde işlem yapılamaz
        $order2 = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'package',
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$order2}/cancel", ['reason' => 'müşteri vazgeçti'])->assertOk();
        $this->postJson("/api/v1/orders/{$order2}/items", ['product_id' => $product->id, 'qty' => 1])->assertUnprocessable();
        $this->putJson("/api/v1/orders/{$order2}/status", ['status' => 'preparing'])->assertUnprocessable();
    }

    public function test_secenekli_kalem_fiyati_ve_kdv_snapshoti(): void
    {
        $table = $this->makeTable($this->a);
        $pizza = $this->makeProduct($this->a, ['name' => 'Pizza', 'price_minor' => 20000, 'tax_rate' => 10.00]);
        $group = $this->attachOptionGroup($this->a, $pizza, ['name' => 'Ekstralar'], [
            ['name' => 'Ekstra peynir', 'price_minor' => 1500],
            ['name' => 'Sucuk', 'price_minor' => 2500],
        ]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $optionIds = $group->options->pluck('id')->all();

        $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $pizza->id,
            'qty' => 2,
            'option_ids' => $optionIds,
        ])->assertCreated();

        // 2 × (20000 + 1500 + 2500) = 48000
        $item = $res->json('order.items.0');
        $this->assertSame(48000, $item['line_total_minor']);
        $this->assertSame(4000, $item['options_price_minor']);
        $this->assertCount(2, $item['options']);
        $this->assertSame(48000, $res->json('order.total_minor'));

        // KDV: brütten pay (48000 - 48000/1.1 = 4364)
        $this->assertSame(4364, $res->json('order.vat_total_minor'));

        // Başka ürünün seçeneği sızdırılamaz
        $other = $this->makeProduct($this->a, ['name' => 'Salata']);
        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $other->id,
            'qty' => 1,
            'option_ids' => [$optionIds[0]],
        ])->assertUnprocessable();
    }

    public function test_zorunlu_secenek_grubu_dogrulanir(): void
    {
        $table = $this->makeTable($this->a);
        $kahve = $this->makeProduct($this->a, ['name' => 'Kahve', 'price_minor' => 8000]);
        $group = $this->attachOptionGroup($this->a, $kahve, [
            'name' => 'Boyut', 'selection_type' => 'single', 'is_required' => true, 'min_select' => 1,
        ], [
            ['name' => 'Küçük', 'price_minor' => 0],
            ['name' => 'Büyük', 'price_minor' => 1000],
        ]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        // Zorunlu grup seçilmedi → 422
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $kahve->id, 'qty' => 1])
            ->assertUnprocessable();

        // Tek-seçimli gruba iki seçenek → 422
        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $kahve->id, 'qty' => 1, 'option_ids' => $group->options->pluck('id')->all(),
        ])->assertUnprocessable();

        // Doğru kullanım
        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $kahve->id, 'qty' => 1, 'option_ids' => [$group->options->last()->id],
        ])->assertCreated();
    }

    public function test_iptal_masayi_bosaltir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        $this->postJson("/api/v1/orders/{$orderId}/cancel", ['reason' => 'müşteri vazgeçti'])->assertOk();

        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);
    }
}
