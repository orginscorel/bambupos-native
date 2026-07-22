<?php

namespace Tests\Feature\Payments;

use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Models\Payment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Eşzamanlılık: bayat sürüm 409; kalanı aşan İKİNCİ ödeme reddi;
 * void sonrası tekrar tahsilat. (Gerçek paralel iki-süreç kanıtı MySQL
 * üzerinde ayrıca koşulur — sqlite test ortamı tek süreçlidir; bkz. rapor.)
 */
class PaymentConcurrencyTest extends TestCase
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

    public function test_ayni_adisyona_iki_tam_odeme_ikincisi_reddedilir(): void
    {
        // İki kasiyer aynı anda tüm kalanı almaya çalışır: ilki kazanır,
        // ikincisi kalan 0 olduğundan reddedilir (aşırı tahsil yasak).
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated();

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertUnprocessable();

        $this->assertSame(10000, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertSame(1, Payment::withoutTenancy()->where('order_id', $orderId)
            ->where('status', 'succeeded')->count());
        $this->assertMoneyInvariant($orderId);
    }

    public function test_bayat_surumle_odeme_409_reddedilir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $version = $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');

        // Başka kasiyer araya girip kısmi ödeme alır → sürüm artar.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 3000,
        ])->assertCreated();

        // Eski sürümle gelen ödeme 409 (kayıp güncelleme yok).
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 7000, 'expected_version' => $version,
        ])->assertStatus(409);

        $this->assertSame(3000, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);

        // Güncel sürümle geçer.
        $current = $this->getJson("/api/v1/orders/{$orderId}")->json('order.version');
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 7000, 'expected_version' => $current,
        ])->assertCreated();

        $this->assertMoneyInvariant($orderId);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);
    }

    public function test_odenmis_adisyona_ek_odeme_alinamaz(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 5000);

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 5000,
        ])->assertCreated();

        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 100,
        ])->assertUnprocessable();

        $this->assertMoneyInvariant($orderId);
    }

    public function test_void_edilen_odemenin_yeri_yeniden_tahsil_edilebilir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->json('payment.id');

        $this->postJson("/api/v1/payments/{$paymentId}/void", ['reason' => 'yanlış yöntem seçildi'])->assertOk();

        // Doğru yöntemle yeniden tahsil.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 10000, 'provider' => 'card_present',
        ])->assertCreated();

        $this->assertMoneyInvariant($orderId);
        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(10000, (int) $order->paid_minor);
        $this->assertSame('paid', (string) $order->status);
    }
}
