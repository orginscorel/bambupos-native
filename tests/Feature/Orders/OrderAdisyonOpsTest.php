<?php

namespace Tests\Feature\Orders;

use App\Modules\Identity\Models\AuditLog;
use App\Modules\Identity\Services\PinService;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Adisyon işlemleri (§12.2) + ikram/indirim/iptal denetimi (§12.3):
 * neden zorunlu, denetim kaydı, eşik üstü indirimde yönetici PIN'i,
 * taşı/birleştir/böl ve toplam tutarlılığı (kuruş kaybı yok).
 */
class OrderAdisyonOpsTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    private function openTableOrder(Table $table): int
    {
        return $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
    }

    public function test_ikram_neden_zorunlu_ve_denetim_kaydina_duser(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Baklava', 'price_minor' => 10000]);
        $orderId = $this->openTableOrder($table);

        $itemId = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])
            ->json('order.items.0.id');

        // Nedensiz ikram reddedilir
        $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/comp", [])->assertUnprocessable();

        $res = $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/comp", ['reason' => 'müşteri memnuniyeti'])->assertOk();

        // İkram edilen kalem toplamdan düşer, değeri ayrıca izlenir
        $this->assertSame(0, $res->json('order.total_minor'));
        $this->assertSame(10000, $res->json('order.comp_total_minor'));
        $this->assertTrue($res->json('order.items.0.is_comp'));

        // Denetim kaydı: tür + neden + yapan (§12.3)
        $log = AuditLog::withoutTenancy()->where('action', 'orders.item_comped')->latest('id')->first();
        $this->assertNotNull($log);
        $this->assertSame('müşteri memnuniyeti', $log->new_values['reason']);
        $this->assertSame($this->a['user']->id, $log->new_values['performed_by']);
        $this->assertSame(10000, $log->new_values['previous_total_minor']);
    }

    public function test_kismi_ikram_kalemi_boler_ve_yalniz_o_adedi_bedava_yapar(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['name' => 'Çay', 'price_minor' => 2000]); // 20 TL
        $orderId = $this->openTableOrder($table);

        $itemId = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 5])
            ->json('order.items.0.id');

        // 5 adetten 2'sini ikram et
        $res = $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/comp", [
            'reason' => 'kampanya', 'qty' => 2,
        ])->assertOk();

        $items = collect($res->json('order.items'));
        // Kalem bölündü: 3 adet ücretli (6000) + 2 adet ikram (0)
        $paid = $items->firstWhere('is_comp', false);
        $comp = $items->firstWhere('is_comp', true);
        $this->assertNotNull($paid);
        $this->assertNotNull($comp);
        $this->assertSame(3, (int) $paid['qty']);
        $this->assertSame(6000, (int) $paid['line_total_minor']);
        $this->assertSame(2, (int) $comp['qty']);
        $this->assertSame(0, (int) $comp['line_total_minor']);

        // Adisyon: ücretli 6000, ikram değeri 4000
        $this->assertSame(6000, $res->json('order.total_minor'));
        $this->assertSame(4000, $res->json('order.comp_total_minor'));
    }

    public function test_esik_alti_indirim_gecer_esik_ustu_yonetici_pin_ister(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 100000]); // 1000 TL
        $orderId = $this->openTableOrder($table);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        // %10 (eşik) altı: onaysız geçer
        $res = $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 10, 'reason' => 'sadakat kartı',
        ])->assertOk();
        $this->assertSame(10000, $res->json('order.discount_minor'));
        $this->assertSame(90000, $res->json('order.total_minor'));

        // TEK İNDİRİM KURALI: indirim varken ikincisi eklenemez (üzerine yazma yok).
        $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 25, 'reason' => 'şikâyet telafisi',
        ])->assertUnprocessable();

        // Değiştirmek için önce KALDIR.
        $this->deleteJson("/api/v1/orders/{$orderId}/discount")
            ->assertOk()
            ->assertJsonPath('order.discount_minor', 0);

        // %25: onaysız REDDEDİLİR (eşik kuralı korunuyor)
        $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 25, 'reason' => 'şikâyet telafisi',
        ])->assertUnprocessable();

        // Yönetici (staff.manage + orders.discount) PIN'i ile geçer
        $manager = $this->a['user']; // tüm izinlere sahip
        app(PinService::class)->setPin($manager, '735962');

        $res = $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 25, 'reason' => 'şikâyet telafisi',
            'approver_email' => $manager->email, 'approver_pin' => '735962',
        ])->assertOk();

        $this->assertSame(25000, $res->json('order.discount_minor'));
        $this->assertSame(75000, $res->json('order.total_minor'));

        // Yanlış PIN reddedilir (önce mevcut indirim kaldırılır ki tek-indirim
        // kuralı değil, PIN kuralı sınansın)
        $this->deleteJson("/api/v1/orders/{$orderId}/discount")->assertOk();
        $this->postJson("/api/v1/orders/{$orderId}/discount", [
            'type' => 'percent', 'value' => 30, 'reason' => 'x deneme',
            'approver_email' => $manager->email, 'approver_pin' => '111222',
        ])->assertUnprocessable();

        // Denetim kaydı düştü (yetkilendiren + yapan + önceki tutar)
        $log = AuditLog::withoutTenancy()->where('action', 'orders.discount_applied')->latest('id')->first();
        $this->assertNotNull($log);
        $this->assertSame($manager->id, $log->new_values['approved_by']);
    }

    public function test_kalem_baska_masaya_tasinir_hedefte_adisyon_acilir(): void
    {
        $table1 = $this->makeTable($this->a);
        $table2 = $this->makeTable($this->a);
        $cola = $this->makeProduct($this->a, ['name' => 'Kola', 'price_minor' => 5000]);
        $ayran = $this->makeProduct($this->a, ['name' => 'Ayran', 'price_minor' => 3000]);

        $orderId = $this->openTableOrder($table1);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $cola->id, 'qty' => 1]);
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $ayran->id, 'qty' => 2]);
        $ayranItem = collect($res->json('order.items'))->firstWhere('name', 'Ayran');

        $res = $this->postJson("/api/v1/orders/{$orderId}/items/{$ayranItem['id']}/move", [
            'table_id' => $table2->id,
        ])->assertOk();

        // Kaynak: yalnız kola kaldı
        $this->assertSame(5000, $res->json('order.total_minor'));

        // Hedef: yeni adisyon açıldı, ayran orada
        $targetId = $res->json('target_order.id');
        $target = $this->getJson("/api/v1/orders/{$targetId}")->json('order');
        $this->assertSame($table2->id, $target['table_id']);
        $this->assertSame(6000, $target['total_minor']);

        // Hedef masa da operasyona girdi
        $this->assertNotSame('available', Table::withoutTenancy()->find($table2->id)->status->value);
    }

    public function test_adisyon_tasima_iki_masanin_durumunu_gunceller(): void
    {
        $table1 = $this->makeTable($this->a);
        $table2 = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a);

        $orderId = $this->openTableOrder($table1);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        $this->postJson("/api/v1/orders/{$orderId}/move", ['table_id' => $table2->id])->assertOk();

        $this->assertSame('available', Table::withoutTenancy()->find($table1->id)->status->value);
        $this->assertSame('order_taken', Table::withoutTenancy()->find($table2->id)->status->value);
    }

    public function test_birlestirme_toplamlari_kurusu_kurusuna_korur(): void
    {
        $table = $this->makeTable($this->a);
        $p1 = $this->makeProduct($this->a, ['price_minor' => 12345]);
        $p2 = $this->makeProduct($this->a, ['price_minor' => 6789]);

        $o1 = $this->openTableOrder($table);
        $this->postJson("/api/v1/orders/{$o1}/items", ['product_id' => $p1->id, 'qty' => 3]); // 37035

        $o2 = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $this->makeTable($this->a)->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$o2}/items", ['product_id' => $p2->id, 'qty' => 7]); // 47523

        $res = $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertOk();

        $this->assertSame(37035 + 47523, $res->json('order.total_minor'));
        $this->assertSame('cancelled', $this->getJson("/api/v1/orders/{$o2}")->json('order.status'));
        $this->assertSame(0, $this->getJson("/api/v1/orders/{$o2}")->json('order.total_minor'));
    }

    public function test_urun_bazli_bolme_toplami_korur(): void
    {
        $table = $this->makeTable($this->a);
        $p1 = $this->makeProduct($this->a, ['name' => 'Çorba', 'price_minor' => 7501]);
        $p2 = $this->makeProduct($this->a, ['name' => 'Pide', 'price_minor' => 18999]);

        $orderId = $this->openTableOrder($table);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p1->id, 'qty' => 2]); // 15002
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p2->id, 'qty' => 1]); // 18999
        $original = $res->json('order.total_minor');
        $pide = collect($res->json('order.items'))->firstWhere('name', 'Pide');

        $res = $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'items', 'item_ids' => [$pide['id']],
        ])->assertOk();

        $remaining = $res->json('order.total_minor');
        $newOrderId = $res->json('new_order.id');
        $split = $this->getJson("/api/v1/orders/{$newOrderId}")->json('order');

        // Kuruş kaybı yok: parçaların toplamı = orijinal
        $this->assertSame($original, $remaining + $split['total_minor']);
        $this->assertSame(18999, $split['total_minor']);
        $this->assertSame($table->id, $split['table_id']); // aynı masada ayrı hesap
    }

    public function test_esit_bolme_kurus_kaybi_olmadan_pay_dagitir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 10001]); // 100,01 TL

        $orderId = $this->openTableOrder($table);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        $res = $this->postJson("/api/v1/orders/{$orderId}/split", ['mode' => 'equal', 'ways' => 3])->assertOk();

        $shares = $res->json('shares_minor');
        $this->assertCount(3, $shares);
        $this->assertSame(10001, array_sum($shares));           // kuruş kaybı yok
        $this->assertSame([3334, 3334, 3333], $shares);         // kalan kuruşlar ilk paylara
    }

    public function test_kisi_bazli_bolme_toplami_dogrulanir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 50000]);

        $orderId = $this->openTableOrder($table);
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1]);

        // Toplamı tutmayan paylar reddedilir
        $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'persons', 'amounts' => [20000, 20000],
        ])->assertUnprocessable();

        $res = $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'persons', 'amounts' => [20000, 30000],
        ])->assertOk();
        $this->assertSame([20000, 30000], $res->json('shares_minor'));
    }

    public function test_istasyona_giden_kalem_silinemez_nedenli_iptal_gerekir(): void
    {
        $table = $this->makeTable($this->a);
        $product = $this->makeProduct($this->a, ['price_minor' => 10000]);

        $orderId = $this->openTableOrder($table);
        $itemId = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $product->id, 'qty' => 1])
            ->json('order.items.0.id');

        $this->putJson("/api/v1/orders/{$orderId}/items/{$itemId}/status", ['status' => 'preparing'])->assertOk();

        // Sessiz silme reddedilir
        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$itemId}")->assertUnprocessable();

        // Nedenli iptal geçer, toplam düşer, kayıt tutulur
        $res = $this->postJson("/api/v1/orders/{$orderId}/items/{$itemId}/cancel", ['reason' => 'yanlış girildi'])->assertOk();
        $this->assertSame(0, $res->json('order.total_minor'));
        $this->assertSame('cancelled', $res->json('order.items.0.status'));

        $log = AuditLog::withoutTenancy()->where('action', 'orders.item_cancelled')->latest('id')->first();
        $this->assertNotNull($log);
        $this->assertSame('yanlış girildi', $log->new_values['reason']);
    }
}
