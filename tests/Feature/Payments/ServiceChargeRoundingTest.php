<?php

namespace Tests\Feature\Payments;

use App\Modules\Orders\Models\Order;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Servis bedeli + nakit yuvarlama (prompt §15): tutar dökümü doğru,
 * yuvarlama sınırlı ve izli, tahsilat sonrası bedel değişmez.
 */
class ServiceChargeRoundingTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    public function test_yuzdeli_servis_bedeli_toplama_eklenir_ve_kalemle_guncellenir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $res = $this->postJson("/api/v1/orders/{$orderId}/service-charge", [
            'type' => 'percent', 'value' => 10, 'reason' => 'servis',
        ])->assertOk();

        $this->assertSame(1000, $res->json('order.service_charge_minor'));
        $this->assertSame(11000, $res->json('order.total_minor'));

        // Yeni kalem → yüzdeli bedel yeniden hesaplanır.
        $p2 = $this->makeProduct($this->a, ['price_minor' => 5000]);
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p2->id, 'qty' => 1])->assertCreated();

        $this->assertSame(1500, $res->json('order.service_charge_minor')); // %10 × 150
        $this->assertSame(16500, $res->json('order.total_minor'));

        // Tam tahsilat: toplam (servis bedeli dahil) kuruşu kuruşuna.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 16500,
        ])->assertCreated();
        $this->assertMoneyInvariant($orderId);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);
    }

    public function test_sabit_servis_bedeli_ve_kaldirma(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $res = $this->postJson("/api/v1/orders/{$orderId}/service-charge", [
            'type' => 'amount', 'value' => 750, 'reason' => 'sabit servis',
        ])->assertOk();
        $this->assertSame(10750, $res->json('order.total_minor'));

        $res = $this->deleteJson("/api/v1/orders/{$orderId}/service-charge")->assertOk();
        $this->assertSame(0, $res->json('order.service_charge_minor'));
        $this->assertSame(10000, $res->json('order.total_minor'));
    }

    public function test_tahsilat_baslayinca_servis_bedeli_degistirilemez(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 4000,
        ])->assertCreated();

        $this->postJson("/api/v1/orders/{$orderId}/service-charge", [
            'type' => 'percent', 'value' => 10,
        ])->assertUnprocessable();
    }

    public function test_nakit_yuvarlama_kalani_adima_yuvarlar_ve_iz_birakir(): void
    {
        // 87,37 TL'lik adisyon; adım 25 kuruş → 87,25'e yuvarlanır (-12).
        $orderId = $this->makeOrderWithTotal($this->a, 8737);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 8725, 'round' => true,
        ])->assertCreated();

        $order = $res->json('order');
        $this->assertSame(-12, $order['rounding_minor']);
        $this->assertSame(8725, $order['total_minor']);
        $this->assertSame('paid', $order['status']);
        $this->assertMoneyInvariant($orderId);

        // İz: rounding_applied olayı düştü.
        $events = $this->getJson("/api/v1/orders/{$orderId}")->json('order.events');
        $this->assertNotEmpty(array_filter($events, fn (array $e) => $e['type'] === 'rounding_applied'));
    }

    public function test_yuvarlamasiz_nakit_odeme_tutari_degistirmez(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 8737);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 8737,
        ])->assertCreated();

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(0, (int) $order->rounding_minor);
        $this->assertSame(8737, (int) $order->total_minor);
        $this->assertMoneyInvariant($orderId);
    }
}
