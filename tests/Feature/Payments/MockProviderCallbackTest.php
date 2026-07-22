<?php

namespace Tests\Feature\Payments;

use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Providers\MockPosProvider;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Mock POS sağlayıcısının senaryo yolları + callback güvenliği:
 * "terminale göndermek ödeme tamamlandı demek değildir" kuralının kanıtı.
 */
class MockProviderCallbackTest extends TestCase
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

    public function test_timeout_basarisiz_sayilmaz_sorgu_netlestirir(): void
    {
        // ..98 → terminal TIMEOUT (durum bilinmiyor); ödeme PENDING kalır.
        $orderId = $this->makeOrderWithTotal($this->a, 9898);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9898,
        ])->assertCreated();

        $this->assertSame('pending', $res->json('payment.status'));
        $this->assertSame('timeout', $res->json('provider_result.status'));
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);

        // Sorgu: sağlayıcıda işlem ASLINDA onaylanmış → şimdi tamamlanır.
        $paymentId = $res->json('payment.id');
        $q = $this->postJson("/api/v1/payments/{$paymentId}/query")->assertOk();

        $this->assertSame('succeeded', $q->json('payment.status'));
        $this->assertSame(9898, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertSame('paid', $q->json('order.status'));
        $this->assertMoneyInvariant($orderId);
    }

    public function test_sorguda_reddedilen_odeme_failed_olur(): void
    {
        // ..96 → send PENDING; query DECLINED.
        $orderId = $this->makeOrderWithTotal($this->a, 9696);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9696,
        ])->assertCreated();

        $this->assertSame('pending', $res->json('payment.status'));

        $q = $this->postJson('/api/v1/payments/'.$res->json('payment.id').'/query')->assertOk();

        $this->assertSame('failed', $q->json('payment.status'));
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertNotSame('paid', $q->json('order.status')); // başarısız ödeme kapatmaz
        $this->assertMoneyInvariant($orderId);
    }

    public function test_imzasiz_veya_bozuk_imzali_callback_reddedilir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 9797);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9797,
        ])->assertCreated();

        $payload = [
            'reference' => $res->json('payment.reference'),
            'provider_txn_id' => $res->json('payment.provider_txn_id'),
            'status' => 'approved',
            'amount_minor' => 9797,
        ];

        // İmzasız
        $this->postJson('/api/v1/public/payments/callback/mock', $payload)->assertStatus(400);

        // Bozuk imza
        $this->postSignedCallback($payload, signature: str_repeat('0', 64))->assertStatus(400);

        // Eski zaman damgası (replay penceresi dışı) — imza doğru olsa bile RED.
        $old = time() - 3600;
        $this->postSignedCallback($payload, timestamp: $old)->assertStatus(400);

        // Hiçbiri işlemedi.
        $this->assertSame('pending', (string) Payment::withoutTenancy()
            ->where('reference', $payload['reference'])->first()->status);
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
    }

    public function test_declined_callback_odemeyi_failed_yapar(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 9797);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9797,
        ])->assertCreated();

        $this->postSignedCallback([
            'reference' => $res->json('payment.reference'),
            'provider_txn_id' => $res->json('payment.provider_txn_id'),
            'status' => 'declined',
            'amount_minor' => 9797,
        ])->assertOk();

        $this->assertSame('failed', (string) Payment::withoutTenancy()
            ->where('reference', $res->json('payment.reference'))->first()->status);
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);
    }

    public function test_cevrimdisi_terminal_ve_durum_ucu(): void
    {
        $this->getJson('/api/v1/payments/terminal-status?provider=mock&terminal_id=OFFLINE')
            ->assertOk()->assertJson(['online' => false]);

        $this->getJson('/api/v1/payments/terminal-status?provider=mock&terminal_id=T1')
            ->assertOk()->assertJson(['online' => true]);

        // Çevrimdışı terminale gönderim → pending (timeout), tahsilat yok.
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 10000, 'terminal_id' => 'OFFLINE',
        ])->assertCreated();

        $this->assertSame('pending', $res->json('payment.status'));
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
    }

    public function test_imza_yardimcisi_dogru_hmac_uretir(): void
    {
        $ts = '1700000000';
        $body = '{"a":1}';

        $this->assertSame(
            hash_hmac('sha256', $ts.'.'.$body, MockPosProvider::secret()),
            MockPosProvider::sign($ts, $body),
        );
    }
}
