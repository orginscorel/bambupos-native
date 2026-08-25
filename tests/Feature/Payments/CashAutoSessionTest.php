<?php

namespace Tests\Feature\Payments;

use App\Modules\Payments\Models\CashRegister;
use App\Modules\Payments\Models\CashSession;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * KASA HER ZAMAN VARDIR (otomatik oturum).
 *
 * Eskiden kasiyerin ödeme almadan ÖNCE kasa oluşturup oturum açması
 * gerekiyordu; unutulunca tahsilat sessizce oturumsuz kalıyor ve Z raporunun
 * DIŞINDA kalıyordu (defter deliği). Artık açık oturum yoksa şubenin
 * varsayılan kasası (yoksa oluşturulup) otomatik açılır.
 *
 * Elle açılmış oturuma DOKUNULMAZ; çift oturum ÜRETİLMEZ.
 */
class CashAutoSessionTest extends TestCase
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

    public function test_hic_kasa_yokken_odeme_alinirsa_kasa_ve_oturum_otomatik_acilir(): void
    {
        $this->assertSame(0, CashRegister::withoutTenancy()->count());

        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated()->json('payment.id');

        // Kasa + açık oturum kendiliğinden oluştu.
        $this->assertSame(1, CashRegister::withoutTenancy()->count());
        $session = CashSession::withoutTenancy()->where('status', 'open')->first();
        $this->assertNotNull($session);
        $this->assertSame(0, (int) $session->opening_float_minor);

        // Tahsilat oturuma BAĞLANDI → Z raporunun dışında kalmıyor.
        $this->assertDatabaseHas('payments', [
            'id' => $paymentId,
            'cash_session_id' => $session->getKey(),
        ]);
    }

    public function test_elle_acilmis_oturum_varsa_yeni_oturum_acilmaz(): void
    {
        $register = $this->makeRegister($this->a);
        $sessionId = (int) $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 20000,
        ])->assertCreated()->json('session.id');

        $orderId = $this->makeOrderWithTotal($this->a, 5000);
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 5000, 'tendered_minor' => 5000,
        ])->assertCreated();

        $this->assertSame(1, CashSession::withoutTenancy()->where('status', 'open')->count());
        $this->assertSame(1, CashRegister::withoutTenancy()->count());
        $this->assertSame(20000, (int) CashSession::withoutTenancy()->find($sessionId)->opening_float_minor);
    }

    public function test_arka_arkaya_odemeler_tek_otomatik_oturumu_kullanir(): void
    {
        foreach ([10000, 7500, 2500] as $amount) {
            $orderId = $this->makeOrderWithTotal($this->a, $amount);
            $this->postJson("/api/v1/orders/{$orderId}/payments", [
                'method' => 'cash', 'amount_minor' => $amount, 'tendered_minor' => $amount,
            ])->assertCreated();
        }

        $this->assertSame(1, CashRegister::withoutTenancy()->count());
        $this->assertSame(1, CashSession::withoutTenancy()->count());
    }
}
