<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\OrderItem;
use App\Support\Idempotency\Models\IdempotencyKey;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Offline-kuyruk idempotency PROOF (görev B, docs/offline-sync-protocol.md):
 * gövdede `op_id` (uuid) ile addItem çağrısı — Idempotency-Key HEADER'ından
 * BAĞIMSIZ bir katman. Ağ isteğinden çok önce, istemci işlemi kuyruğa
 * eklerken üretilir; geç senkronda bile aynı kalır.
 *
 * Not: bu test paket sqlite (:memory:) test veritabanını kullanır (phpunit.xml)
 * — prod MySQL'e DOKUNMAZ, her koşuda otomatik temizlenir (RefreshDatabase).
 */
class OrderOpIdIdempotencyTest extends TestCase
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

    private function openTableOrder(): int
    {
        $table = $this->makeTable($this->a);

        return $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
    }

    public function test_ayni_op_id_ile_addItem_iki_kez_cagrilinca_urun_iki_kez_eklenmez(): void
    {
        $product = $this->makeProduct($this->a, ['price_minor' => 10000]);
        $orderId = $this->openTableOrder();

        $opId = '11111111-1111-4111-8111-111111111111';
        $payload = ['product_id' => $product->id, 'qty' => 1, 'op_id' => $opId];

        // 1. çağrı: kalem gerçekten eklenir.
        $first = $this->postJson("/api/v1/orders/{$orderId}/items", $payload)->assertCreated();
        $this->assertFalse($first->json('replayed'));
        $this->assertSame(1, OrderItem::withoutTenancy()->where('order_id', $orderId)->count());

        // 2. çağrı: AYNI op_id + AYNI gövde (offline istemcinin senkron tekrarı
        // ya da ağ zaman aşımı sonrası yeniden gönderimi) → İş TEKRAR ÇALIŞMAZ,
        // ilk yanıt aynen döner.
        $second = $this->postJson("/api/v1/orders/{$orderId}/items", $payload)->assertOk();
        $this->assertTrue($second->json('replayed'));

        // Kanıt: ürün İKİ KEZ eklenmedi (tek kalem, adet hâlâ 1) + toplam sabit.
        $this->assertSame(1, OrderItem::withoutTenancy()->where('order_id', $orderId)->count());
        $this->assertSame(1, (int) OrderItem::withoutTenancy()->where('order_id', $orderId)->value('qty'));
        $this->assertSame(10000, $this->getJson("/api/v1/orders/{$orderId}")->json('order.total_minor'));

        // Yanıt gövdesi de birebir aynı (order id, toplam) — gerçek bir replay.
        $this->assertSame($first->json('order.id'), $second->json('order.id'));
        $this->assertSame($first->json('order.total_minor'), $second->json('order.total_minor'));

        // idempotency_keys tablosunda TEK satır, status=completed.
        $this->assertSame(1, IdempotencyKey::withoutTenancy()->where('op_id', $opId)->count());
        $this->assertSame('completed', IdempotencyKey::withoutTenancy()->where('op_id', $opId)->value('status'));
    }

    public function test_op_id_yoksa_davranis_bugunkuyle_aynidir_iki_ayri_kalem_eklenir(): void
    {
        $product = $this->makeProduct($this->a, ['price_minor' => 5000]);
        $orderId = $this->openTableOrder();

        // op_id GÖNDERİLMEZ → bugünkü davranış: her çağrı bağımsız işlenir.
        // (Aynı ürün + boş not/varyant/opsiyon satırı BİRLEŞİR — mevcut kural,
        // bkz. OrderConcurrencyTest — bu yüzden kanıt adet üzerinden verilir.)
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])
            ->assertCreated();
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])
            ->assertCreated();

        $this->assertSame(1, OrderItem::withoutTenancy()->where('order_id', $orderId)->count());
        $this->assertSame(2, (int) OrderItem::withoutTenancy()->where('order_id', $orderId)->value('qty'));
        $this->assertSame(0, IdempotencyKey::withoutTenancy()->count());
    }

    public function test_ayni_op_id_farkli_govdeyle_gelirse_409_doner(): void
    {
        $product = $this->makeProduct($this->a, ['price_minor' => 10000]);
        $orderId = $this->openTableOrder();

        $opId = '22222222-2222-4222-8222-222222222222';

        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 1, 'op_id' => $opId,
        ])->assertCreated();

        // AYNI op_id, FARKLI adet — istemci hatası/çakışma, sessizce yutulmaz.
        $this->postJson("/api/v1/orders/{$orderId}/items", [
            'product_id' => $product->id, 'qty' => 2, 'op_id' => $opId,
        ])->assertStatus(409);

        $this->assertSame(1, (int) OrderItem::withoutTenancy()->where('order_id', $orderId)->value('qty'));
    }

    public function test_op_id_kiraciya_ozeldir(): void
    {
        auth('web')->logout();
        $b = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);

        $opId = '33333333-3333-4333-8333-333333333333';

        $productA = $this->makeProduct($this->a);
        $orderA = $this->openTableOrder();

        $this->postJson("/api/v1/orders/{$orderA}/items", [
            'product_id' => $productA->id, 'qty' => 1, 'op_id' => $opId,
        ])->assertCreated();

        $this->actingAs($b['user']);
        $this->a = $b; // openTableOrder/makeProduct $this->a'yı kullanır
        $productB = $this->makeProduct($b);
        $orderB = $this->openTableOrder();

        // Kiracı B AYNI op_id ile kendi siparişine ekleyebilir (çakışma yok).
        $res = $this->postJson("/api/v1/orders/{$orderB}/items", [
            'product_id' => $productB->id, 'qty' => 1, 'op_id' => $opId,
        ])->assertCreated();

        $this->assertFalse($res->json('replayed'));
    }
}
