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
 * PARA DEĞİŞMEZLERİ (görev §3) — her senaryodan sonra
 * assertMoneyInvariant SUM(payments)==orders.paid_minor'ı doğrular.
 */
class PaymentInvariantsTest extends TestCase
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

    public function test_kismi_odemeler_toplami_adisyonu_kurus_kaybi_olmadan_kapatir(): void
    {
        // 100,00 TL'lik adisyon; 3'e bölünmüş paylar: 3334+3333+3333 kuruş.
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $shares = $this->postJson("/api/v1/orders/{$orderId}/split", ['mode' => 'equal', 'ways' => 3])
            ->assertOk()->json('shares_minor');

        $this->assertSame(10000, array_sum($shares)); // bölme payları toplamı = adisyon (değişmez)
        $this->assertSame([3334, 3333, 3333], $shares);

        foreach ($shares as $i => $share) {
            $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
                'method' => 'cash', 'amount_minor' => $share,
            ])->assertCreated();

            $expectedStatus = $i < 2 ? 'partially_paid' : 'paid';
            $this->assertSame($expectedStatus, $res->json('order.status'));
            $this->assertMoneyInvariant($orderId);
        }

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(10000, (int) $order->paid_minor);       // kuruş kaybı yok
        $this->assertSame(0, 10000 - (int) $order->paid_minor);   // kalan 0
        $this->assertNotNull($order->closed_at);
    }

    public function test_asiri_tahsil_reddedilir_fazlasi_ancak_bahsis_olarak_alinir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 5000);

        // Kalan 50,00 TL iken 60,00 TL ödeme REDDEDİLİR.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 6000,
        ])->assertUnprocessable();

        $this->assertMoneyInvariant($orderId);
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);

        // Fazlalık AÇIKÇA bahşiş alanına yazılırsa kabul edilir.
        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 5000, 'tip_minor' => 1000, 'tendered_minor' => 6000,
        ])->assertCreated();

        $this->assertSame('paid', $res->json('order.status'));
        $this->assertSame(1000, $res->json('payment.tip_minor'));
        $this->assertSame(0, $res->json('payment.change_minor')); // 60 verdi, 50+10 bahşiş → para üstü 0
        $this->assertMoneyInvariant($orderId);
    }

    public function test_para_ustu_dogru_hesaplanir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 8750); // 87,50 TL

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 8750, 'tendered_minor' => 10000,
        ])->assertCreated();

        $this->assertSame(1250, $res->json('payment.change_minor')); // 100 - 87,50
        $this->assertSame('paid', $res->json('order.status'));
        $this->assertMoneyInvariant($orderId);
    }

    public function test_basarisiz_odeme_adisyonu_kapatmaz(): void
    {
        // Mock senaryosu ..99 → terminal DECLINED.
        $orderId = $this->makeOrderWithTotal($this->a, 9999);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9999,
        ])->assertCreated();

        $this->assertSame('failed', $res->json('payment.status'));

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(0, (int) $order->paid_minor);           // adisyona İŞLEMEDİ
        $this->assertNotSame('paid', (string) $order->status);    // KAPANMADI
        $this->assertNull($order->closed_at);
        $this->assertMoneyInvariant($orderId);

        // Adisyon hâlâ normal yoldan ödenebilir.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 9999,
        ])->assertCreated();
        $this->assertMoneyInvariant($orderId);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);
    }

    public function test_nakit_kart_karma_ve_birden_fazla_kart(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 30000); // 300 TL

        // 100 nakit + 100 kart (mock onaylı) + 100 kart (kayıt-onaylı POS)
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated();

        $r2 = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 10000,
        ])->assertCreated();
        $this->assertSame('succeeded', $r2->json('payment.status')); // mock senkron onay

        $r3 = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'debit_card', 'amount_minor' => 10000, 'provider' => 'card_present',
        ])->assertCreated();

        $this->assertSame('paid', $r3->json('order.status'));
        $this->assertMoneyInvariant($orderId);

        $this->assertSame(3, Payment::withoutTenancy()->where('order_id', $orderId)->count());
    }

    public function test_terminal_bekleyen_odeme_kalani_rezerve_eder(): void
    {
        // ..97 → terminal PENDING kalır; kalan tutar rezerve edilir.
        $orderId = $this->makeOrderWithTotal($this->a, 9797);

        $res = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'credit_card', 'amount_minor' => 9797,
        ])->assertCreated();

        $this->assertSame('pending', $res->json('payment.status'));

        // Bekleyen ödeme adisyona İŞLEMEDİ (gönderim ≠ tahsilat)…
        $this->assertSame(0, (int) Order::withoutTenancy()->find($orderId)->paid_minor);
        $this->assertMoneyInvariant($orderId);

        // …ama kalan rezerve: aynı tutarı nakit almaya kalkmak reddedilir
        // (çifte tahsilat önlenir).
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 9797,
        ])->assertUnprocessable();
    }

    public function test_void_tahsilati_geri_alir_ve_adisyonu_yeniden_acar(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated()->json('payment.id');

        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);

        $res = $this->postJson("/api/v1/payments/{$paymentId}/void", ['reason' => 'yanlış adisyona alındı'])->assertOk();

        $this->assertSame('cancelled', $res->json('payment.status'));

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(0, (int) $order->paid_minor);
        $this->assertSame('bill_requested', (string) $order->status); // yeniden açıldı
        $this->assertNull($order->closed_at);
        $this->assertMoneyInvariant($orderId);
    }

    public function test_kismi_ve_tam_iade(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 20000);

        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 20000,
        ])->assertCreated()->json('payment.id');

        // Kısmi iade 50 TL
        $res = $this->postJson("/api/v1/payments/{$paymentId}/refund", [
            'amount_minor' => 5000, 'reason' => 'eksik servis',
        ])->assertCreated();

        $this->assertSame('partially_refunded', $res->json('payment.status'));
        $this->assertMoneyInvariant($orderId);

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(5000, (int) $order->refunded_minor);
        $this->assertSame('paid', (string) $order->status); // kısmi iade adisyonu Refunded yapmaz

        // İade toplamı ödemeyi aşamaz
        $this->postJson("/api/v1/payments/{$paymentId}/refund", [
            'amount_minor' => 16000, 'reason' => 'deneme',
        ])->assertUnprocessable();

        // Kalanın tamamı iade → ödeme refunded, adisyon Refunded
        $this->postJson("/api/v1/payments/{$paymentId}/refund", [
            'amount_minor' => 15000, 'reason' => 'müşteri memnuniyetsiz',
        ])->assertCreated();

        $this->assertMoneyInvariant($orderId);
        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(20000, (int) $order->refunded_minor);
        $this->assertSame('refunded', (string) $order->status);
        $this->assertSame('refunded', (string) Payment::withoutTenancy()->find($paymentId)->status);
    }

    public function test_odeme_kaydinin_para_alanlari_sessizce_degistirilemez(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated()->json('payment.id');

        $payment = Payment::withoutTenancy()->find($paymentId);
        $payment->amount_minor = 1; // sessiz değişiklik girişimi

        $this->expectException(\LogicException::class);
        $payment->save();
    }

    public function test_kiraciya_gore_bolunmus_kisiler_toplami_tam_tahsil_edilir(): void
    {
        // Kişi bazlı bölme: elle paylar; toplam tutmayan reddedilir (Orders),
        // tutan paylar tek tek tahsil edilir ve adisyon kuruşu kuruşuna kapanır.
        $orderId = $this->makeOrderWithTotal($this->a, 12345);

        $shares = $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'persons', 'amounts' => [5000, 4345, 3000],
        ])->assertOk()->json('shares_minor');

        $this->assertSame(12345, array_sum($shares));

        foreach ($shares as $share) {
            $this->postJson("/api/v1/orders/{$orderId}/payments", [
                'method' => 'cash', 'amount_minor' => $share,
            ])->assertCreated();
        }

        $this->assertMoneyInvariant($orderId);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);
    }

    public function test_urun_bazli_bolme_yeni_adisyon_ayri_tahsil_edilir(): void
    {
        // Ürün bazlı bölme Orders'ta yeni adisyon açar; iki adisyon ayrı ödenir.
        $table = $this->makeTable($this->a);
        $p1 = $this->makeProduct($this->a, ['price_minor' => 4000]);
        $p2 = $this->makeProduct($this->a, ['price_minor' => 6000]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p1->id, 'qty' => 1])->assertCreated();
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p2->id, 'qty' => 1])->assertCreated();

        $itemId = collect($res->json('order.items'))->firstWhere('unit_price_minor', 6000)['id'];

        $newOrderId = $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'items', 'item_ids' => [$itemId],
        ])->assertOk()->json('new_order.id');

        // Toplamlar kuruşu kuruşuna korunur
        $this->assertSame(4000, (int) Order::withoutTenancy()->find($orderId)->total_minor);
        $this->assertSame(6000, (int) Order::withoutTenancy()->find($newOrderId)->total_minor);

        $this->postJson("/api/v1/orders/{$orderId}/payments", ['method' => 'cash', 'amount_minor' => 4000])->assertCreated();
        $this->postJson("/api/v1/orders/{$newOrderId}/payments", ['method' => 'credit_card', 'amount_minor' => 6000])->assertCreated();

        $this->assertMoneyInvariant($orderId);
        $this->assertMoneyInvariant($newOrderId);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($orderId)->status);
        $this->assertSame('paid', (string) Order::withoutTenancy()->find($newOrderId)->status);
    }
}
