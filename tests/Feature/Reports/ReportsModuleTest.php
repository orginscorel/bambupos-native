<?php

namespace Tests\Feature\Reports;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Raporlar (Faz-10): izin kapısı, kiracı izolasyonu, satış/finans
 * matematiği ve rol bazlı pano bölümleri.
 */
class ReportsModuleTest extends TestCase
{
    use InteractsWithOrders, InteractsWithPayments, InteractsWithTenancy, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPermissions();
    }

    public function test_rapor_ucu_izinsiz_403_izinli_200(): void
    {
        $waiter = $this->makeTenantWithUser(['orders.view', 'orders.create', 'orders.update', 'catalog.view', 'tables.view']);
        $this->actingAs($waiter['user']);

        $this->getJson('/api/v1/reports/sales-summary')->assertForbidden();
        $this->get('/panel/raporlar')->assertForbidden();

        // Bir sonraki kiracı/kullanıcı kurulurken TenantContext hâlâ önceki
        // oturumdaki kullanıcıya düşmesin diye açıkça çıkış yapılır (bkz.
        // PaymentIsolationTest'teki aynı desen).
        auth('web')->logout();
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);

        $this->getJson('/api/v1/reports/sales-summary')->assertOk();
        $this->get('/panel/raporlar')->assertOk();
    }

    public function test_bilinmeyen_rapor_404_yabanci_sube_yoksayilir(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $this->getJson('/api/v1/reports/olmayan-rapor')->assertNotFound();

        // ŞUBE KAPSAMI: istekten gelen yabancı branch_id YOK SAYILIR — rapor
        // daima kullanıcının geçerli şubesine süzülür (sızıntı değil, 422 değil).
        $this->getJson('/api/v1/reports/sales-summary?branch_id='.$b['branch']->id)
            ->assertOk();
    }

    /**
     * Ciro = YALNIZ KAPANAN (ödenmiş) adisyonlar (2026-07-23 düzeltmesi —
     * bkz. SalesReportService docblock). Açık (ödenmemiş) bir adisyon bu
     * testte AYRICA kurulup Ciro'ya SIZMADIĞI doğrulanır.
     */
    public function test_satis_ozeti_matematigi_ve_kiraci_izolasyonu(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        // B kiracısında satış (A raporuna SIZMAMALI)
        $this->actingAs($b['user']);
        $bOrder = $this->makeOrderWithTotal($b, 99900);
        $this->postJson("/api/v1/orders/{$bOrder}/payments", [
            'method' => 'cash', 'amount_minor' => 99900, 'tendered_minor' => 99900,
        ])->assertCreated();

        // A kiracısında 100,00 ve 200,00 TL'lik iki KAPANAN (ödenmiş) adisyon
        $this->actingAs($a['user']);
        $order1 = $this->makeOrderWithTotal($a, 10000);
        $this->postJson("/api/v1/orders/{$order1}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated();
        $order2 = $this->makeOrderWithTotal($a, 20000);
        $this->postJson("/api/v1/orders/{$order2}/payments", [
            'method' => 'cash', 'amount_minor' => 20000, 'tendered_minor' => 20000,
        ])->assertCreated();

        // AYRICA açık (ödenmemiş) bir adisyon — Ciro'ya SIZMAMALI.
        $this->makeOrderWithTotal($a, 50000);

        $data = $this->getJson('/api/v1/reports/sales-summary')
            ->assertOk()
            ->json('data');

        $this->assertSame(2, $data['current']['orders']);
        $this->assertSame(30000, $data['current']['revenue_minor']);
        $this->assertSame(15000, $data['current']['avg_basket_minor']);
    }

    public function test_odeme_yontemi_kirilimi_payments_kaynagindan(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $register = $this->makeRegister($a);
        $this->postJson('/api/v1/cash/sessions', [
            'cash_register_id' => $register->id, 'opening_float_minor' => 0,
        ])->assertCreated();

        $orderId = $this->makeOrderWithTotal($a, 10000);
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tip_minor' => 500, 'tendered_minor' => 10500,
        ])->assertCreated();

        $orderId2 = $this->makeOrderWithTotal($a, 5000);
        $this->postJson("/api/v1/orders/{$orderId2}/payments", [
            'method' => 'credit_card', 'amount_minor' => 5000,
        ])->assertCreated();

        $data = $this->getJson('/api/v1/reports/finance-payment-methods')->assertOk()->json('data');

        $this->assertSame(15000, $data['total_minor']);

        $byMethod = collect($data['rows'])->keyBy('method');
        $this->assertSame(10000, $byMethod['cash']['amount_minor']);
        $this->assertSame(500, $byMethod['cash']['tips_minor']);
        $this->assertSame(5000, $byMethod['credit_card']['amount_minor']);
    }

    public function test_gun_sonu_raporu_gercek_veriyle_hesaplanir(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $orderId = $this->makeOrderWithTotal($a, 10000);
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated();

        $data = $this->getJson('/api/v1/reports/ops-eod')->assertOk()->json('data');

        $this->assertSame(1, $data['orders']);
        $this->assertSame(10000, $data['revenue_minor']);
        $this->assertSame(10000, $data['avg_basket_minor']);
        $this->assertSame(1, $data['orders_opened']);
        $this->assertSame(1, $data['orders_closed']); // tam ödendi → kapandı
        $this->assertSame(10000, $data['collected_minor']);
        $this->assertSame(1, $data['collected_count']);
        $this->assertSame(0, $data['cancelled_orders']);

        // Receivables (cari) modülü kurulu; bu kiracının hiç açık carisi
        // yok — DÜRÜSTÇE available=true + 0 (uydurma bakiye yok, 500 yok).
        $this->assertTrue($data['open_receivables_available']);
        $this->assertSame(0, $data['open_receivables_count']);
        $this->assertSame(0, $data['open_receivables_total_minor']);
    }

    public function test_acik_cariler_hic_kayit_yokken_bos_liste_doner(): void
    {
        $this->assertTrue(\Illuminate\Support\Facades\Schema::hasTable('receivables'),
            'Receivables modülü artık kurulu; ReceivablesReportService gerçek şemayı okumalı.');

        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $data = $this->getJson('/api/v1/reports/ops-open-receivables')->assertOk()->json('data');

        $this->assertTrue($data['available']);
        $this->assertSame([], $data['rows']);
        $this->assertSame(0, $data['total_minor']);
        $this->assertSame(0, $data['count']);
    }

    public function test_mutabakat_nakit_pos_ve_sistem_tutarlarini_ayirir(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $cashOrder = $this->makeOrderWithTotal($a, 10000);
        $this->postJson("/api/v1/orders/{$cashOrder}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated();

        $cardOrder = $this->makeOrderWithTotal($a, 5000);
        $this->postJson("/api/v1/orders/{$cardOrder}/payments", [
            'method' => 'credit_card', 'amount_minor' => 5000,
        ])->assertCreated();

        $data = $this->getJson('/api/v1/reports/finance-reconciliation')->assertOk()->json('data');

        $this->assertSame(10000, $data['cash_minor']);
        $this->assertSame(1, $data['cash_count']);
        $this->assertSame(5000, $data['pos_minor']);
        $this->assertSame(1, $data['pos_count']);
        $this->assertSame(0, $data['other_minor']);
        $this->assertSame(15000, $data['payments_total_minor']);

        // İki adisyon da tam ödendiği için kapandı; sistemin defteri de aynı toplamı göstermeli.
        $this->assertSame(2, $data['orders_closed_count']);
        $this->assertSame(15000, $data['orders_paid_minor']);
        $this->assertSame(0, $data['difference_minor']);
        $this->assertFalse($data['has_cash_sessions']);
    }

    /**
     * Receivables modülünün GERÇEK şeması (`receivables`: name/phone/
     * balance_minor/tenant_id) üzerinden ReceivablesReportService'in
     * doğru hesapladığını, kiracı izolasyonuna uyduğunu ve
     * bakiyesi 0 olan carinin listede GÖRÜNMEDİĞİNİ doğrular.
     */
    public function test_acik_cariler_gercek_semadan_dogru_hesaplar(): void
    {
        $a = $this->makeTenantWithUser();
        $b = $this->makeTenantWithUser();

        $this->asTenant($a['tenant'], function () use ($a): void {
            \App\Modules\Receivables\Models\Receivable::factory()->create([
                'tenant_id' => $a['tenant']->id, 'name' => 'Ahmet Bey', 'phone' => '5551112233', 'balance_minor' => 15000,
            ]);
            \App\Modules\Receivables\Models\Receivable::factory()->create([
                'tenant_id' => $a['tenant']->id, 'name' => 'Ödendi Cari', 'phone' => null, 'balance_minor' => 0, // bakiyesi yok — LİSTEDE OLMAMALI
            ]);
        });
        $this->asTenant($b['tenant'], function () use ($b): void {
            \App\Modules\Receivables\Models\Receivable::factory()->create([
                'tenant_id' => $b['tenant']->id, 'name' => "B'nin Carisi", 'phone' => null, 'balance_minor' => 99900, // farklı kiracı — SIZMAMALI
            ]);
        });

        $this->actingAs($a['user']);
        $data = $this->getJson('/api/v1/reports/ops-open-receivables')->assertOk()->json('data');

        $this->assertTrue($data['available']);
        $this->assertSame(1, $data['count']);
        $this->assertSame(15000, $data['total_minor']);
        $this->assertSame('Ahmet Bey', $data['rows'][0]['name']);
        $this->assertSame('5551112233', $data['rows'][0]['phone']);
        $this->assertSame(15000, $data['rows'][0]['balance_minor']);

        // ops-eod özetine de doğru yansır.
        $eod = $this->getJson('/api/v1/reports/ops-eod')->assertOk()->json('data');
        $this->assertTrue($eod['open_receivables_available']);
        $this->assertSame(15000, $eod['open_receivables_total_minor']);
    }

    public function test_urun_karlilik_maliyetsiz_urunde_kar_uydurmaz(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        // Maliyeti bilinen ürün: satış 100,00 (KDV %10 dahil) maliyet 40,00
        $table = $this->makeTable($a);
        $costly = $this->makeProduct($a, ['price_minor' => 10000, 'cost_minor' => 4000]);
        $free = $this->makeProduct($a, ['price_minor' => 5000, 'cost_minor' => null]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $costly->id, 'qty' => 1])->assertCreated();
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $free->id, 'qty' => 1])->assertCreated();

        $data = $this->getJson('/api/v1/reports/product-profitability')->assertOk()->json('data');

        $rows = collect($data['rows'])->keyBy('name');

        // Maliyetli ürün: net = 10000 - KDV payı; kâr = net - 4000
        $withCost = $rows[$costly->name];
        $this->assertTrue($withCost['has_cost']);
        $this->assertSame(9091, $withCost['net_minor']);   // 10000 brüt, %10 KDV dahil
        $this->assertSame(5091, $withCost['profit_minor']);

        // Maliyetsiz ürün: kâr HESAPLANMAZ (null), 0 uydurulmaz
        $noCost = $rows[$free->name];
        $this->assertFalse($noCost['has_cost']);
        $this->assertNull($noCost['profit_minor']);
        $this->assertNull($noCost['margin']);
        $this->assertSame(1, $data['missing_cost_count']);
    }

    /**
     * İkram (#7): ikram edilen kalemler gelir GETİRMEZ ama stok/maliyet
     * TÜKETİR. Kârlılık ve gün sonu raporunda adet/tutar/maliyet AYRI
     * görünmeli; net kâr = brüt kâr − ikram maliyeti (maliyeti kârdan düşer).
     */
    public function test_ikram_maliyeti_karlilik_ve_gun_sonu_raporunda_ayrilir(): void
    {
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $table = $this->makeTable($a);
        $sold = $this->makeProduct($a, ['price_minor' => 10000, 'cost_minor' => 4000, 'tax_rate' => 10.00]);
        $comped = $this->makeProduct($a, ['price_minor' => 5000, 'cost_minor' => 2000, 'tax_rate' => 10.00]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $sold->id, 'qty' => 1])->assertCreated();
        $compItemId = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $comped->id, 'qty' => 2])
            ->assertCreated()->json('order.items.1.id');
        // 2 × 5000 = 10000 bedelsiz ikram (neden zorunlu)
        $this->postJson("/api/v1/orders/{$orderId}/items/{$compItemId}/comp", ['reason' => 'müşteri memnuniyeti'])->assertOk();

        // Kalan ödenecek = 10000 (yalnız satılan kalem); öde → adisyon kapanır.
        $this->postJson("/api/v1/orders/{$orderId}/payments", [
            'method' => 'cash', 'amount_minor' => 10000, 'tendered_minor' => 10000,
        ])->assertCreated();

        // Kârlılık: ikram özeti ayrı (adet/tutar/maliyet); ürün satırlarında ikram YOK.
        $profit = $this->getJson('/api/v1/reports/product-profitability')->assertOk()->json('data');
        $this->assertSame(2, $profit['comp']['qty']);            // 2 adet ikram
        $this->assertSame(1, $profit['comp']['items']);          // tek kalem satırı (qty=2)
        $this->assertSame(10000, $profit['comp']['value_minor']); // 2 × 5000 bedelsiz değer
        $this->assertSame(4000, $profit['comp']['cost_minor']);   // 2 × 2000 tüketilen maliyet
        $this->assertSame(0, $profit['comp']['missing_cost_items']);
        // İkram edilen ürün, kârlılık (gelir) satırlarında GÖRÜNMEZ.
        $this->assertNotContains($comped->name, array_column($profit['rows'], 'name'));

        // Gün sonu: aynı ikram maliyeti + adet burada da ayrı.
        $eod = $this->getJson('/api/v1/reports/ops-eod')->assertOk()->json('data');
        $this->assertSame(2, $eod['comp_count']);
        $this->assertSame(10000, $eod['comp_minor']);
        $this->assertSame(4000, $eod['comp_cost_minor']);
        $this->assertSame(0, $eod['comp_missing_cost_items']);
        // Borca taşınan yok → ciro=tahsilat farkı yok.
        $this->assertSame(0, $eod['debt_transferred_balance_minor']);
    }

    public function test_pano_bolumleri_izinlere_gore_suzulur(): void
    {
        // Sahip: tüm bölümler
        $owner = $this->makeTenantWithUser();
        $this->actingAs($owner['user']);
        $sections = $this->getJson('/api/v1/reports/dashboard')->assertOk()->json('sections');

        $this->assertArrayHasKey('today', $sections);
        $this->assertArrayHasKey('trend', $sections);
        $this->assertArrayHasKey('payment_mix', $sections);
        $this->assertArrayHasKey('open_orders', $sections);
        $this->assertArrayHasKey('occupancy', $sections);
        $this->assertArrayHasKey('cash', $sections);

        // Garson: finans bölümü YOK, operasyon VAR
        auth('web')->logout();
        $waiter = $this->makeTenantWithUser(['orders.view', 'tables.view', 'catalog.view']);
        $this->actingAs($waiter['user']);
        $sections = $this->getJson('/api/v1/reports/dashboard')->assertOk()->json('sections');

        $this->assertArrayNotHasKey('today', $sections);
        $this->assertArrayNotHasKey('payment_mix', $sections);
        $this->assertArrayNotHasKey('cash', $sections);
        $this->assertArrayHasKey('open_orders', $sections);
        $this->assertArrayHasKey('occupancy', $sections);

        // Mutfak: hiçbir pano bölümü dönmez (finans sızıntısı yok)
        auth('web')->logout();
        $kitchen = $this->makeTenantWithUser(['kds.view']);
        $this->actingAs($kitchen['user']);
        $sections = $this->getJson('/api/v1/reports/dashboard')->assertOk()->json('sections');

        $this->assertSame([], $sections);
    }
}
