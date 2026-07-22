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
 * "Aynı ödeme iki kez işlenemez" (görev §3):
 *  - Idempotency-Key ile çift dokunma / ağ tekrarı,
 *  - imzalı callback replay'i,
 *  - UNIQUE(provider, provider_txn_id).
 */
class PaymentIdempotencyTest extends TestCase
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

    public function test_ayni_idempotency_key_odemeyi_cogaltmaz(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $headers = ['Idempotency-Key' => 'kasa-1-dokunma-42'];
        $payload = ['method' => 'cash', 'amount_minor' => 4000];

        $first = $this->postJson("/api/v1/orders/{$orderId}/payments", $payload, $headers)->assertCreated();
        $this->assertFalse($first->json('replayed'));

        // Çift dokunma: AYNI anahtar → saklanan yanıt döner, İKİNCİ tahsilat OLMAZ.
        $second = $this->postJson("/api/v1/orders/{$orderId}/payments", $payload, $headers)->assertOk();
        $this->assertTrue($second->json('replayed'));

        $this->assertSame(1, Payment::withoutTenancy()->where('order_id', $orderId)->count());
        $this->assertSame(4000, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);

        // Farklı anahtar = gerçek yeni ödeme.
        $this->postJson("/api/v1/orders/{$orderId}/payments", $payload, ['Idempotency-Key' => 'kasa-1-dokunma-43'])
            ->assertCreated();
        $this->assertSame(8000, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);
    }

    public function test_callback_replay_ikinci_kez_islemez(): void
    {
        // ..97 → pending; callback ile tamamlanır.
        $orderId = $this->makeOrderWithTotal($this->a, 9797);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9797,
        ])->assertCreated();

        $reference = $res->json('payment.reference');
        $txn = $res->json('payment.provider_txn_id');

        $payload = [
            'reference' => $reference,
            'provider_txn_id' => $txn,
            'status' => 'approved',
            'amount_minor' => 9797,
        ];

        // 1. callback: ödemeyi tamamlar.
        $this->postSignedCallback($payload)->assertOk();
        $this->assertSame('succeeded', (string) Payment::withoutTenancy()->where('reference', $reference)->first()->status);
        $this->assertSame(9797, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);

        // 2. AYNI callback (replay): 200 döner ama İKİNCİ kez İŞLEMEZ.
        $this->postSignedCallback($payload)->assertOk();
        $this->assertSame(9797, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertSame(1, Payment::withoutTenancy()->where('order_id', $orderId)->count());
        $this->assertMoneyInvariant($orderId);
    }

    public function test_ayni_saglayici_islem_kimligi_ikinci_kez_kaydedilemez(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 20000);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 5000,
        ])->assertCreated();

        $txn = $res->json('payment.provider_txn_id');
        $this->assertNotNull($txn);

        // UNIQUE(provider, provider_txn_id): aynı sağlayıcı işlemi ikinci satır açamaz.
        $dupe = new Payment([
            'kind' => 'payment', 'method' => 'cash', 'status' => 'succeeded',
            'amount_minor' => 5000, 'currency' => 'TRY', 'provider' => 'cash',
        ]);
        $dupe->tenant_id = $this->a['tenant']->id;
        $dupe->branch_id = $this->a['branch']->id;
        $dupe->order_id = $orderId;
        $dupe->reference = Payment::generateReference();
        $dupe->provider_txn_id = $txn;

        $this->expectException(\Illuminate\Database\QueryException::class);
        $dupe->save();
    }

    public function test_tutar_uyusmayan_callback_islemez_suspect_isaretler(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 9797);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9797,
        ])->assertCreated();

        // Sağlayıcı FARKLI tutar bildiriyor → işlem YAPILMAZ, suspect+alarm.
        $this->postSignedCallback([
            'reference' => $res->json('payment.reference'),
            'provider_txn_id' => $res->json('payment.provider_txn_id'),
            'status' => 'approved',
            'amount_minor' => 5000,
        ])->assertStatus(400);

        $payment = Payment::withoutTenancy()->where('reference', $res->json('payment.reference'))->first();
        $this->assertSame('pending', (string) $payment->status);
        $this->assertTrue((bool) $payment->suspect);
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);
    }
}
