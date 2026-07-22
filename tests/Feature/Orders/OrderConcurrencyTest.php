<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\OrderItem;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Eşzamanlılık / idempotency (prompt §12.4):
 *  - Aynı Idempotency-Key ile gelen İKİNCİ istek kalem ÇOĞALTMAZ,
 *    saklanan yanıtı `replayed: true` ile aynen döner.
 *  - Bayat sürüm numarası (optimistic locking) 409 ile reddedilir.
 *  (Gerçek paralel iki-süreç kanıtı MySQL üzerinde ayrıca koşulur;
 *   bkz. rapor — sqlite test ortamı tek süreçlidir.)
 */
class OrderConcurrencyTest extends TestCase
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

    public function test_ayni_idempotency_key_kalem_cogaltmaz(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 10000]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $payload = ['product_id' => $product->id, 'qty' => 1];
        $headers = ['Idempotency-Key' => 'garson-tablet-abc-123'];

        // 1. istek: kalem eklenir
        $first = $this->postJson("/api/v1/orders/{$orderId}/items", $payload, $headers)->assertCreated();
        $this->assertFalse($first->json('replayed'));

        // 2. istek (AYNI anahtar — çift dokunma / ağ tekrarı): ÇOĞALTMAZ
        $second = $this->postJson("/api/v1/orders/{$orderId}/items", $payload, $headers)->assertOk();
        $this->assertTrue($second->json('replayed'));

        $this->assertSame(1, OrderItem::withoutTenancy()->where('order_id', $orderId)->count());
        $this->assertSame(10000, $this->getJson("/api/v1/orders/{$orderId}")->json('order.total_minor'));

        // Farklı anahtar = gerçek yeni istek: eklenir
        $this->postJson("/api/v1/orders/{$orderId}/items", $payload, ['Idempotency-Key' => 'garson-tablet-abc-124'])
            ->assertCreated();
        $this->assertSame(2, OrderItem::withoutTenancy()->where('order_id', $orderId)->count());
    }

    public function test_idempotency_anahtari_kiraciya_ozeldir(): void
    {
        // İkinci kiracı, A'nın oturum bağlamı dışında kurulur.
        auth('web')->logout();
        $b = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);

        $tableA = $this->makeTable($this->a);
        $productA = $this->makeProduct($this->a);

        $orderA = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $tableA->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderA}/items", ['product_id' => $productA->id, 'qty' => 1], [
            'Idempotency-Key' => 'ortak-anahtar',
        ])->assertCreated();

        // Kiracı B aynı anahtarla kendi siparişine ekleyebilir (çakışma yok)
        $this->actingAs($b['user']);
        $tableB = $this->makeTable($b);
        $productB = $this->makeProduct($b);

        $orderB = $this->postJson('/api/v1/orders', [
            'branch_id' => $b['branch']->id, 'channel' => 'table', 'table_id' => $tableB->id,
        ])->json('order.id');

        $res = $this->postJson("/api/v1/orders/{$orderB}/items", ['product_id' => $productB->id, 'qty' => 1], [
            'Idempotency-Key' => 'ortak-anahtar',
        ])->assertCreated();

        $this->assertFalse($res->json('replayed'));
    }

    public function test_bayat_surum_409_reddedilir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $version = $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');

        // 1. garson kalem ekler → sürüm artar
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])->assertCreated();

        // 2. garson ESKİ sürümle indirim uygulamaya çalışır → 409
        $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 5, 'reason' => 'sadakat',
            'expected_version' => $version,
        ])->assertStatus(409);

        // Güncel sürümle geçer
        $current = $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');
        $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 5, 'reason' => 'sadakat',
            'expected_version' => $current,
        ])->assertOk();
    }

    public function test_her_mutasyon_surumu_artirir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $v0 = $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');
        $v1 = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])->json('order.version');
        $v2 = $this->postJson("/api/v1/orders/{$orderId}/request-bill")->json('order.version');

        $this->assertGreaterThan($v0, $v1);
        $this->assertGreaterThan($v1, $v2);
    }
}
