<?php

namespace Tests\Feature\Payments;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiracı izolasyonu (ADR-004): yabancı kiracının adisyonu/ödemesi/kasası
 * görünmez ve işlenemez (404 — varlık sızıntısı da yok).
 */
class PaymentIsolationTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    private int $aOrderId;

    private int $aPaymentId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();

        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
        $this->aOrderId = $this->makeOrderWithTotal($this->a, 10000);
        $this->aPaymentId = (int) $this->postJson("/api/v1/orders/{$this->aOrderId}/payments", [
            'method' => 'cash', 'amount_minor' => 4000,
        ])->json('payment.id');

        auth('web')->logout();
        $this->b = $this->makeTenantWithUser();
        $this->actingAs($this->b['user']);
    }

    public function test_yabanci_adisyona_odeme_alinamaz(): void
    {
        $this->postJson("/api/v1/orders/{$this->aOrderId}/payments", [
            'method' => 'cash', 'amount_minor' => 1000,
        ])->assertNotFound();

        $this->getJson("/api/v1/orders/{$this->aOrderId}/payments")->assertNotFound();
    }

    public function test_yabanci_odeme_sorgulanamaz_void_iade_edilemez(): void
    {
        $this->postJson("/api/v1/payments/{$this->aPaymentId}/query")->assertNotFound();
        $this->postJson("/api/v1/payments/{$this->aPaymentId}/void", ['reason' => 'sızma denemesi'])->assertNotFound();
        $this->postJson("/api/v1/payments/{$this->aPaymentId}/refund", ['amount_minor' => 100, 'reason' => 'sızma denemesi'])->assertNotFound();
    }

    public function test_bekleyen_adisyon_listesi_yabanci_kayit_sizdirmaz(): void
    {
        $orders = $this->getJson('/api/v1/payments/pending-orders')->assertOk()->json('orders');

        $this->assertSame([], array_filter($orders, fn (array $o) => (int) $o['id'] === $this->aOrderId));
    }

    public function test_yabanci_kasa_ve_oturum_gorunmez(): void
    {
        // A kiracısında kasa + oturum kur.
        auth('web')->logout();
        $this->actingAs($this->a['user']);
        $register = $this->makeRegister($this->a);
        $session = $this->openSessionFor($this->a, $register);

        // B kiracısı: liste boş; doğrudan erişim 404.
        auth('web')->logout();
        $this->actingAs($this->b['user']);

        $this->assertSame([], $this->getJson('/api/v1/cash/registers')->assertOk()->json('registers'));
        $this->getJson("/api/v1/cash/sessions/{$session->id}")->assertNotFound();
        $this->postJson("/api/v1/cash/sessions/{$session->id}/close", ['counted_cash_minor' => 0])->assertNotFound();
        $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 0,
        ])->assertUnprocessable(); // scoped find → "Kasa bulunamadı"
    }

    public function test_idempotency_anahtari_kiraciya_ozeldir(): void
    {
        // A'da kullanılmış anahtar B'nin ödemesini engellemez/sızdırmaz.
        auth('web')->logout();
        $this->actingAs($this->a['user']);
        $this->postJson("/api/v1/orders/{$this->aOrderId}/payments", [
            'method' => 'cash', 'amount_minor' => 1000,
        ], ['Idempotency-Key' => 'ortak-anahtar'])->assertCreated();

        auth('web')->logout();
        $this->actingAs($this->b['user']);
        $bOrder = $this->makeOrderWithTotal($this->b, 5000);

        $res = $this->postJson("/api/v1/orders/{$bOrder}/payments", [
            'method' => 'cash', 'amount_minor' => 5000,
        ], ['Idempotency-Key' => 'ortak-anahtar'])->assertCreated();

        $this->assertFalse($res->json('replayed'));
        $this->assertMoneyInvariant($bOrder);
    }
}
