<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Public (oturumsuz) QR sipariş ucu: kimlik yalnız token (ADR-008),
 * onay-bekliyor akışı, masa senkronu, idempotency, rotasyon 410,
 * yabancı ürün sızması ve durum takibi.
 */
class PublicOrderTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
    }

    public function test_token_ile_siparis_onay_bekler_ve_masa_guncellenir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Mercimek Çorbası', 'price_minor' => 8000, 'qr_price_minor' => 7500]);

        $res = $this->postJson('/api/v1/public/orders', [
            'token' => $table->qr_token,
            'customer_name' => 'Masa müşterisi',
            'items' => [['product_id' => $product->id, 'qty' => 2]],
        ])->assertCreated();

        $this->assertSame('pending_approval', $res->json('order.status'));
        $this->assertSame(2 * 7500, $res->json('order.total_minor')); // QR kanal fiyatı
        $this->assertNotEmpty($res->json('order.public_token'));

        // İç kimlikler sızmaz
        $this->assertArrayNotHasKey('id', $res->json('order'));
        $this->assertArrayNotHasKey('version', $res->json('order'));

        // Masa: "Sipariş bekliyor" (onay bekleyen QR siparişi)
        $this->assertSame('awaiting_order', Table::withoutTenancy()->find($table->id)->status->value);

        // Durum takibi (10 sn polling ucu)
        $publicToken = $res->json('order.public_token');
        $this->getJson("/api/v1/public/orders/{$publicToken}?token={$table->qr_token}")
            ->assertOk()
            ->assertJsonPath('order.status', 'pending_approval');

        // Yanlış QR token'la sipariş durumu okunamaz
        $other = $this->makeTable($this->a);
        $this->getJson("/api/v1/public/orders/{$publicToken}?token={$other->qr_token}")->assertNotFound();

        // Garson onaylar → sipariş alındı
        $this->actingAs($this->a['user']);
        $orderId = Order::withoutTenancy()->where('public_token', $publicToken)->first()->id;
        $this->postJson("/api/v1/orders/{$orderId}/approve")->assertOk();
        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_gecersiz_ve_rotasyonlu_token_reddedilir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $payload = ['items' => [['product_id' => $product->id, 'qty' => 1]]];

        // Geçersiz token → 404
        $this->postJson('/api/v1/public/orders', $payload + ['token' => 'AAAAAAAAAAAAAAAAAAAAAAAAAA'])->assertNotFound();

        // Rotasyonlanmış eski token → 410
        $oldToken = $table->qr_token;
        $table->rotateQrToken();
        $this->postJson('/api/v1/public/orders', $payload + ['token' => $oldToken])->assertStatus(410);

        // Yeni token çalışır
        $this->postJson('/api/v1/public/orders', $payload + ['token' => $table->fresh()->qr_token])->assertCreated();
    }

    public function test_yabanci_kiracinin_urunu_tokenla_siparis_edilemez(): void
    {
        $b = $this->makeTenantWithUser();
        $table = $this->makeTable($this->a);
        $bProduct = $this->makeProduct($b);

        $this->postJson('/api/v1/public/orders', [
            'token' => $table->qr_token,
            'items' => [['product_id' => $bProduct->id, 'qty' => 1]],
        ])->assertUnprocessable();

        $this->assertSame(0, Order::withoutTenancy()->where('tenant_id', $this->a['tenant']->id)->count());
    }

    public function test_ayni_idempotency_key_siparisi_cogaltmaz(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $payload = ['token' => $table->qr_token, 'items' => [['product_id' => $product->id, 'qty' => 1]]];
        $headers = ['Idempotency-Key' => 'musteri-cihaz-xyz-1'];

        $first = $this->postJson('/api/v1/public/orders', $payload, $headers)->assertCreated();
        $second = $this->postJson('/api/v1/public/orders', $payload, $headers)->assertOk();

        $this->assertTrue($second->json('replayed'));
        $this->assertSame($first->json('order.public_token'), $second->json('order.public_token'));
        $this->assertSame(1, Order::withoutTenancy()->where('tenant_id', $this->a['tenant']->id)->count());
    }

    public function test_qr_kanalina_kapali_urun_reddedilir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['channels' => ['pos']]); // yalnız salon satışı

        $this->postJson('/api/v1/public/orders', [
            'token' => $table->qr_token,
            'items' => [['product_id' => $product->id, 'qty' => 1]],
        ])->assertUnprocessable();
    }

    public function test_rate_limit_uygulanir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $payload = ['token' => $table->qr_token, 'items' => [['product_id' => $product->id, 'qty' => 1]]];

        $limit = (int) config('orders.public_rate_per_minute', 10);

        for ($i = 0; $i < $limit; $i++) {
            $this->postJson('/api/v1/public/orders', $payload);
        }

        $this->postJson('/api/v1/public/orders', $payload)->assertStatus(429);
    }
}
