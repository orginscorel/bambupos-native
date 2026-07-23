<?php

namespace Tests\Feature\Receivables;

use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Receivables\Models\Receivable;
use App\Modules\Receivables\Models\ReceivableTransaction;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithPayments;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Borçlar/Cari modülü (Adisyon-Cari görev §2–3):
 *  - "Adisyonu borca taşı": kalan tutar cariye borç yazılır, adisyon
 *    TERMİNAL 'debt_transferred' olur (paid DEĞİL), masa boşalır.
 *  - Tahsilat: aşırı tahsilat reddedilir, bakiye tam düşer.
 *  - PARA KORUNUMU: Σ(ledger amount_minor) = receivables.balance_minor.
 */
class ReceivablesModuleTest extends TestCase
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

    private function makeReceivable(string $name = 'Ahmet Bey'): int
    {
        return $this->postJson('/api/v1/receivables', ['name' => $name, 'phone' => '5551112233'])
            ->assertCreated()->json('receivable.id');
    }

    public function test_cari_olusturulur_ve_guncellenir(): void
    {
        $res = $this->postJson('/api/v1/receivables', [
            'name' => 'Mehmet Usta', 'phone' => '5559998877', 'note' => 'Komşu esnaf',
        ])->assertCreated();

        $this->assertSame('Mehmet Usta', $res->json('receivable.name'));
        $this->assertSame(0, $res->json('receivable.balance_minor'));

        $id = $res->json('receivable.id');
        $this->putJson("/api/v1/receivables/{$id}", ['note' => 'Güncellendi'])->assertOk()
            ->assertJsonPath('receivable.note', 'Güncellendi');
    }

    public function test_adisyonu_borca_tasima_masayi_bosaltir_ve_adisyonu_terminal_yapar(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 15000);
        $order = Order::withoutTenancy()->find($orderId);
        $table = Table::withoutTenancy()->find($order->table_id);

        $this->assertSame('order_taken', $table->status->value);

        $receivableId = $this->makeReceivable();

        $res = $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $receivableId,
            'reason' => 'Müşteri sonra ödeyecek',
        ])->assertOk();

        $this->assertSame('debt_transferred', $res->json('order.status'));
        $this->assertNotSame('paid', $res->json('order.status'));

        $fresh = Order::withoutTenancy()->find($orderId);
        $this->assertSame('debt_transferred', $fresh->status);
        $this->assertSame(0, (int) $fresh->paid_minor); // gerçek tahsilat YOK
        $this->assertSame(15000, (int) $fresh->debt_amount_minor);
        $this->assertSame($receivableId, $fresh->debt_receivable_id);
        $this->assertNotNull($fresh->closed_at);

        // Masa BOŞALIR (yeni müşteri sipariş verebilir).
        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);

        // Cari bakiyesi TAM kalan tutar kadar arttı.
        $receivable = Receivable::withoutTenancy()->find($receivableId);
        $this->assertSame(15000, (int) $receivable->balance_minor);

        // İz: order_events + audit_logs + ledger.
        $this->assertDatabaseHas('order_events', ['order_id' => $orderId, 'type' => 'debt_transferred']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'orders.debt_transferred', 'entity_id' => $orderId]);
        $ledger = ReceivableTransaction::withoutTenancy()->where('receivable_id', $receivableId)->where('type', 'debt_transfer')->first();
        $this->assertNotNull($ledger);
        $this->assertSame(15000, (int) $ledger->amount_minor);
        $this->assertSame($orderId, $ledger->order_id);

        // Masa boşaldı: yeni müşteri aynı masada sipariş verebilir (tek-adisyon kuralı ihlal edilmez).
        $newOrder = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated();
        $this->assertNotSame($orderId, $newOrder->json('order.id'));
    }

    public function test_kismi_odenmis_adisyon_borca_tasininca_yalniz_kalan_tasinir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 20000);

        $this->postJson("/api/v1/orders/{$orderId}/pay", ['amount_minor' => 8000, 'method' => 'cash'])->assertOk();
        $this->assertSame('partially_paid', Order::withoutTenancy()->find($orderId)->status);

        $receivableId = $this->makeReceivable();
        $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $receivableId, 'reason' => 'kalanı sonra ödeyecek',
        ])->assertOk();

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame('debt_transferred', $order->status);
        $this->assertSame(8000, (int) $order->paid_minor); // önceki kısmi ödeme KORUNUR
        $this->assertSame(12000, (int) $order->debt_amount_minor); // yalnız KALAN taşınır

        $this->assertSame(12000, (int) Receivable::withoutTenancy()->find($receivableId)->balance_minor);
    }

    public function test_kapali_adisyon_borca_tasinamaz(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $this->postJson("/api/v1/orders/{$orderId}/pay", ['amount_minor' => 10000, 'method' => 'cash'])->assertOk();
        $this->assertSame('paid', Order::withoutTenancy()->find($orderId)->status);

        $receivableId = $this->makeReceivable();
        $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $receivableId, 'reason' => 'x',
        ])->assertUnprocessable();
    }

    public function test_tahsilat_bakiyeyi_dogru_dusurur_asiri_tahsilat_reddedilir(): void
    {
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $receivableId = $this->makeReceivable();
        $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $receivableId, 'reason' => 'sonra ödeyecek',
        ])->assertOk();

        // Kısmi tahsilat
        $res = $this->postJson("/api/v1/receivables/{$receivableId}/collect", [
            'amount_minor' => 4000, 'method' => 'cash',
        ])->assertOk();
        $this->assertSame(6000, $res->json('receivable.balance_minor'));

        // Aşırı tahsilat REDDEDİLİR (para değişmezi)
        $this->postJson("/api/v1/receivables/{$receivableId}/collect", [
            'amount_minor' => 6001, 'method' => 'cash',
        ])->assertUnprocessable();
        $this->assertSame(6000, (int) Receivable::withoutTenancy()->find($receivableId)->balance_minor);

        // Kalanın tamamı tahsil edilir → bakiye SIFIRLANIR
        $res = $this->postJson("/api/v1/receivables/{$receivableId}/collect", [
            'amount_minor' => 6000, 'method' => 'card',
        ])->assertOk();
        $this->assertSame(0, $res->json('receivable.balance_minor'));
    }

    /** PARA KORUNUMU: birden çok borç + kısmi tahsilat sonrası defter toplamı bakiyeye eşit. */
    public function test_para_korunumu_ledger_toplami_bakiyeye_esittir(): void
    {
        $receivableId = $this->makeReceivable();

        $o1 = $this->makeOrderWithTotal($this->a, 12345);
        $this->postJson("/api/v1/orders/{$o1}/transfer-to-debt", ['receivable_id' => $receivableId, 'reason' => 'borç 1'])->assertOk();

        $o2 = $this->makeOrderWithTotal($this->a, 6789);
        $this->postJson("/api/v1/orders/{$o2}/transfer-to-debt", ['receivable_id' => $receivableId, 'reason' => 'borç 2'])->assertOk();

        $this->postJson("/api/v1/receivables/{$receivableId}/collect", ['amount_minor' => 5000, 'method' => 'cash'])->assertOk();
        $this->postJson("/api/v1/receivables/{$receivableId}/collect", ['amount_minor' => 3000, 'method' => 'card'])->assertOk();

        $receivable = Receivable::withoutTenancy()->find($receivableId);
        $ledgerSum = (int) ReceivableTransaction::withoutTenancy()->where('receivable_id', $receivableId)->sum('amount_minor');

        $this->assertSame($ledgerSum, (int) $receivable->balance_minor);
        $this->assertSame(12345 + 6789 - 5000 - 3000, (int) $receivable->balance_minor);
    }

    public function test_yabanci_kiracinin_carisine_adisyon_baglanamaz(): void
    {
        // İkinci kiracı A'nın oturum bağlamı DIŞINDA kurulur (OrderConcurrencyTest
        // ile aynı desen) — aksi halde BelongsToTenant bağlam uyuşmazlığı fırlatır.
        auth('web')->logout();
        $b = $this->makeTenantWithUser();
        $bReceivableId = $this->asTenant($b['tenant'], function () use ($b): int {
            $r = new Receivable(['name' => 'Yabancı Cari']);
            $r->created_by_id = $b['user']->id;
            $r->save();

            return $r->id;
        });
        $this->actingAs($this->a['user']);

        $orderId = $this->makeOrderWithTotal($this->a, 10000);

        $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $bReceivableId, 'reason' => 'yabancı cari denemesi',
        ])->assertUnprocessable();
    }

    public function test_yetki_garson_tasiyabilir_kasiyer_tahsil_eder(): void
    {
        // Siparişler sahip (tüm izinler) hesabıyla önceden açılır — kasiyerin
        // orders.create izni yok, aşağıdaki rol geçişlerinden ETKİLENMEMESİ
        // için iki adisyon da BAŞTAN kurulur.
        $orderId = $this->makeOrderWithTotal($this->a, 10000);
        $order2 = $this->makeOrderWithTotal($this->a, 5000);
        $receivableId = $this->makeReceivable();

        $waiterRole = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $waiterRole->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()
                ->whereIn('key', ['orders.view', 'orders.create', 'orders.update', 'receivables.view', 'receivables.transfer'])
                ->pluck('id')->all(),
        );
        $waiter = User::factory()->create(['tenant_id' => $this->a['tenant']->id, 'branch_id' => $this->a['branch']->id]);
        $waiter->roles()->sync([$waiterRole->id]);

        $cashierRole = Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $cashierRole->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()
                ->whereIn('key', ['receivables.view', 'receivables.collect'])
                ->pluck('id')->all(),
        );
        $cashier = User::factory()->create(['tenant_id' => $this->a['tenant']->id, 'branch_id' => $this->a['branch']->id]);
        $cashier->roles()->sync([$cashierRole->id]);

        // Garson taşıyabilir ama TAHSİL EDEMEZ.
        $this->actingAs($waiter);
        $this->postJson("/api/v1/orders/{$orderId}/transfer-to-debt", [
            'receivable_id' => $receivableId, 'reason' => 'garson taşıdı',
        ])->assertOk();
        $this->postJson("/api/v1/receivables/{$receivableId}/collect", ['amount_minor' => 1000, 'method' => 'cash'])
            ->assertForbidden();

        // Kasiyer tahsil EDEBİLİR ama taşıyamaz (izni yok).
        $this->actingAs($cashier);
        $this->postJson("/api/v1/receivables/{$receivableId}/collect", ['amount_minor' => 1000, 'method' => 'cash'])
            ->assertOk();

        $this->postJson("/api/v1/orders/{$order2}/transfer-to-debt", [
            'receivable_id' => $receivableId, 'reason' => 'kasiyer denemesi',
        ])->assertForbidden();
    }
}
