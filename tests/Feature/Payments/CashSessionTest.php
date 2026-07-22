<?php

namespace Tests\Feature\Payments;

use App\Modules\Payments\Models\CashMovement;
use App\Modules\Payments\Models\CashSession;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kasa yönetimi (prompt §16): açılış/hareket/sayım/fark/kapanış (Z),
 * defter değişmezliği (ters kayıt), çoklu kasa, Z numarası.
 */
class CashSessionTest extends TestCase
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

    public function test_tam_kasa_akisi_beklenen_sayilan_fark_ve_z_raporu(): void
    {
        $register = $this->makeRegister($this->a);

        // Açılış: 200,00 TL
        $sessionId = $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 20000,
        ])->assertCreated()->json('session.id');

        // Nakit satış 100,00 + bahşiş 10,00 (çekmeceye 110 girer)
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tip_minor' => 1000, 'tendered_minor' => 11000,
        ])->assertCreated();

        // Kart satışı 50,00 (çekmeceye GİRMEZ, Z kırılımına girer)
        $orderId2 = $this->makeOrderWithTotal($this->a, 5000);
        $this->postJson("/api/v1/orders/{$orderId2}/payments", [
            'method' => 'credit_card', 'amount_minor' => 5000,
        ])->assertCreated();

        // Masraf 30,00 + avans 20,00 + nakit giriş 15,00
        $this->postJson("/api/v1/cash/sessions/{$sessionId}/movements", [
            'type' => 'expense', 'amount_minor' => 3000, 'reason' => 'temizlik malzemesi',
        ])->assertCreated();
        $this->postJson("/api/v1/cash/sessions/{$sessionId}/movements", [
            'type' => 'advance', 'amount_minor' => 2000, 'reason' => 'personel avans',
        ])->assertCreated();
        $this->postJson("/api/v1/cash/sessions/{$sessionId}/movements", [
            'type' => 'cash_in', 'amount_minor' => 1500, 'reason' => 'bozuk para',
        ])->assertCreated();

        // X raporu (açıkken canlı): beklenen = 200+110-30-20+15 = 275,00
        $x = $this->getJson("/api/v1/cash/sessions/{$sessionId}/report")->assertOk()->json('report');
        $this->assertSame(27500, $x['expected_cash_minor']);
        $this->assertSame('open', $x['status']);
        $this->assertSame(1000, $x['tips_total_minor']);

        // Yöntem kırılımı: nakit 100, kredi kartı 50.
        $methods = collect($x['by_method'])->keyBy('method');
        $this->assertSame(10000, $methods['cash']['collected_minor']);
        $this->assertSame(5000, $methods['credit_card']['collected_minor']);

        // Kapanış: 270,00 sayıldı → fark -5,00 (eksik).
        $close = $this->postJson("/api/v1/cash/sessions/{$sessionId}/close", [
            'counted_cash_minor' => 27000, 'closing_note' => 'aksam kapanisi',
        ])->assertOk();

        $this->assertSame(27500, $close->json('session.expected_cash_minor'));
        $this->assertSame(27000, $close->json('session.counted_cash_minor'));
        $this->assertSame(-500, $close->json('session.difference_minor'));

        // Z raporu donduruldu.
        $z = $this->getJson("/api/v1/cash/sessions/{$sessionId}/report")->assertOk()->json('report');
        $this->assertSame('closed', $z['status']);
        $this->assertSame(27500, $z['expected_cash_minor']);
        $this->assertSame(-500, $z['difference_minor']);
        $this->assertSame(15000, $z['payments_total_minor']);
    }

    public function test_ayni_kasada_ikinci_oturum_acilamaz_z_numarasi_artar(): void
    {
        $register = $this->makeRegister($this->a);

        $s1 = $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 0,
        ])->assertCreated();
        $this->assertSame(1, $s1->json('session.z_number'));

        // Açıkken ikinci oturum RED.
        $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 0,
        ])->assertUnprocessable();

        // Kapat → yeni oturum Z#2.
        $this->postJson('/api/v1/cash/sessions/'.$s1->json('session.id').'/close', ['counted_cash_minor' => 0])->assertOk();

        $s2 = $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 0,
        ])->assertCreated();
        $this->assertSame(2, $s2->json('session.z_number'));

        // FARKLI kasada eşzamanlı oturum serbest (çoklu kasa).
        $register2 = $this->makeRegister($this->a, 'Bar Kasası');
        $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register2->id, 'opening_float_minor' => 0,
        ])->assertCreated();
    }

    public function test_kasa_hareketi_sessizce_degistirilemez_ve_silinemez(): void
    {
        $register = $this->makeRegister($this->a);
        $session = $this->openSessionFor($this->a, $register, 0);

        $movementId = $this->postJson("/api/v1/cash/sessions/{$session->id}/movements", [
            'type' => 'cash_in', 'amount_minor' => 5000, 'reason' => 'test giriş',
        ])->assertCreated()->json('movement.id');

        $movement = CashMovement::withoutTenancy()->find($movementId);

        // Tutar değiştirme girişimi → istisna.
        try {
            $movement->amount_minor = 1;
            $movement->save();
            $this->fail('Kasa hareketi tutarı değiştirilebildi — defter değişmezliği İHLAL.');
        } catch (\LogicException) {
            // beklenen
        }

        // Silme girişimi → istisna.
        try {
            CashMovement::withoutTenancy()->find($movementId)->delete();
            $this->fail('Kasa hareketi silinebildi — defter değişmezliği İHLAL.');
        } catch (\LogicException) {
            // beklenen
        }

        $this->assertSame(5000, (int) CashMovement::withoutTenancy()->find($movementId)->amount_minor);
    }

    public function test_duzeltme_ters_kayitla_yapilir_ve_iz_birakir(): void
    {
        $register = $this->makeRegister($this->a);
        $session = $this->openSessionFor($this->a, $register, 10000);

        $movementId = $this->postJson("/api/v1/cash/sessions/{$session->id}/movements", [
            'type' => 'expense', 'amount_minor' => 7000, 'reason' => 'yanlış girilen masraf',
        ])->assertCreated()->json('movement.id');

        // Beklenen: 100 - 70 = 30
        $this->assertSame(3000, $session->fresh()->expectedCashMinor());

        // Ters kayıt.
        $reversal = $this->postJson("/api/v1/cash/movements/{$movementId}/reverse", [
            'reason' => 'hatalı tutar girildi',
        ])->assertCreated();

        $this->assertSame('correction', $reversal->json('movement.type'));
        $this->assertSame('in', $reversal->json('movement.direction'));
        $this->assertSame($movementId, $reversal->json('movement.reverses_id'));

        // Beklenen düzeldi: 100.
        $this->assertSame(10000, $session->fresh()->expectedCashMinor());

        // Orijinal kayıt DURUYOR ve ters kayda bağlı (iz).
        $original = CashMovement::withoutTenancy()->find($movementId);
        $this->assertSame(7000, (int) $original->amount_minor);
        $this->assertNotNull($original->reversed_by_id);

        // Aynı hareket İKİNCİ kez ters kayıtlanamaz.
        $this->postJson("/api/v1/cash/movements/{$movementId}/reverse", ['reason' => 'tekrar'])->assertUnprocessable();
    }

    public function test_kapanan_oturum_dondurulur(): void
    {
        $register = $this->makeRegister($this->a);
        $session = $this->openSessionFor($this->a, $register, 0);

        $this->postJson("/api/v1/cash/sessions/{$session->id}/close", ['counted_cash_minor' => 0])->assertOk();

        // Kapalı oturuma hareket eklenemez.
        $this->postJson("/api/v1/cash/sessions/{$session->id}/movements", [
            'type' => 'cash_in', 'amount_minor' => 100, 'reason' => 'geç kayıt',
        ])->assertUnprocessable();

        // İkinci kez kapatılamaz.
        $this->postJson("/api/v1/cash/sessions/{$session->id}/close", ['counted_cash_minor' => 999])->assertUnprocessable();

        // Model düzeyinde de dondurulmuştur.
        $closed = CashSession::withoutTenancy()->find($session->id);
        $closed->counted_cash_minor = 999999;

        $this->expectException(\LogicException::class);
        $closed->save();
    }

    public function test_nakit_void_ve_iade_cekmece_defterine_yansir(): void
    {
        $register = $this->makeRegister($this->a);
        $session = $this->openSessionFor($this->a, $register, 0);

        // Nakit 100 al → beklenen 100.
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $paymentId = $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->json('payment.id');
        $this->assertSame(10000, $session->fresh()->expectedCashMinor());

        // Void → ters kayıt → beklenen 0.
        $this->postJson("/api/v1/payments/{$paymentId}/void", ['reason' => 'hatalı tahsilat'])->assertOk();
        $this->assertSame(0, $session->fresh()->expectedCashMinor());

        // Yeniden al ve kısmi iade et → beklenen 100-40=60.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000,
        ])->assertCreated();
        $newPaymentId = (int) \App\Modules\Payments\Models\Payment::withoutTenancy()
            ->where('order_id', $orderId)->where('status', 'succeeded')->orderByDesc('id')->value('id');

        $this->postJson("/api/v1/payments/{$newPaymentId}/refund", [
            'amount_minor' => 4000, 'reason' => 'ürün iade',
        ])->assertCreated();

        $this->assertSame(6000, $session->fresh()->expectedCashMinor());
        $this->assertMoneyInvariant($orderId);
    }
}
