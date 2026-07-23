<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Adisyon-Cari kuralı: "Masada birden fazla açık adisyon olamaz — ne
 * sipariş gelirse aynı adisyona yazılır." (kullanıcı kararı, 2026-07-23)
 *
 * Gerçek eşzamanlı (çok-süreçli) yarış kanıtı MariaDB üzerinde ayrıca
 * koşuldu ve raporda belgelendi (sqlite test ortamı tek süreçlidir —
 * OrderConcurrencyTest'teki mevcut kural burada da geçerli): 8 paralel
 * `php` süreci aynı masaya `OrderService::open()` çağırdı, tam 1 adisyon
 * oluştu, diğer 7'si aynı adisyona idempotent döndü.
 *
 * Burada doğrulanan: (1) uygulama-katmanı idempotent davranış (garson/QR
 * uçları), (2) DB-düzeyi SON HAT güvencesi — orders_tenant_table_open_slot_unique
 * + tetikleyiciler — servisi bypass eden HAM bir ikinci INSERT bile
 * reddedilir (sqlite'ta da, bkz. migration).
 */
class SingleOpenOrderTest extends TestCase
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

    public function test_masaya_ikinci_ac_istegi_yeni_adisyon_acmaz_var_olani_doner(): void
    {
        $table = $this->makeTable($this->a);

        $first = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated();

        $second = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertOk(); // 200, DEĞİL 201 — yeni kaynak oluşmadı

        $third = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertOk();

        $this->assertSame($first->json('order.id'), $second->json('order.id'));
        $this->assertSame($first->json('order.id'), $third->json('order.id'));

        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }

    public function test_qr_ikinci_musteri_ayni_masaya_siparis_verince_var_olan_adisyona_eklenir(): void
    {
        $table = $this->makeTable($this->a);
        $corba = $this->makeProduct($this->a, ['name' => 'Çorba', 'price_minor' => 5000]);
        $pide = $this->makeProduct($this->a, ['name' => 'Pide', 'price_minor' => 8000]);

        // Garson masayı açtı (QR'dan BAĞIMSIZ bir kanaldan).
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $corba->id, 'qty' => 1])->assertCreated();

        auth('web')->logout();

        // Aynı masadaki BAŞKA bir müşteri QR'dan sipariş verir — adisyon
        // kapanmadan yeni adisyon AÇILAMAZ; kalem var olana eklenir.
        $res = $this->postJson('/api/v1/public/orders', [
            'token' => $table->fresh()->qr_token,
            'items' => [['product_id' => $pide->id, 'qty' => 1]],
        ])->assertCreated();

        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)->count());

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame(13000, (int) $order->total_minor); // 5000 + 8000, TEK adisyonda
        $this->assertSame(2, \App\Modules\Orders\Models\OrderItem::withoutTenancy()->where('order_id', $orderId)->count());
    }

    public function test_db_duzeyi_son_hat_guvencesi_ham_ikinci_insert_reddedilir(): void
    {
        $table = $this->makeTable($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');

        $this->expectException(\Illuminate\Database\QueryException::class);

        // OrderService'i (kilit + kontrol) BYPASS eden ham bir ikinci satır —
        // yalnız orders_tenant_table_open_slot_unique + tetikleyiciler onu durdurur.
        DB::table('orders')->insert([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
            'table_id' => $table->id,
            'status' => 'placed',
            'channel' => 'table',
            'currency' => 'TRY',
            'version' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_hedefte_acik_adisyon_varken_adisyon_tasima_reddedilir(): void
    {
        $table1 = $this->makeTable($this->a);
        $table2 = $this->makeTable($this->a);

        $order1 = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table1->id,
        ])->json('order.id');

        $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table2->id,
        ])->assertCreated();

        // table2'de ZATEN açık adisyon var → order1 oraya taşınamaz.
        $this->postJson("/api/v1/orders/{$order1}/move", ['table_id' => $table2->id])
            ->assertUnprocessable();
    }

    public function test_bol_sonrasi_ana_adisyon_kapansa_bile_yeni_siparis_kalan_acik_parcaya_yazilir(): void
    {
        $table = $this->makeTable($this->a);
        $corba = $this->makeProduct($this->a, ['name' => 'Çorba', 'price_minor' => 5000]);
        $pide = $this->makeProduct($this->a, ['name' => 'Pide', 'price_minor' => 8000]);
        $ekstra = $this->makeProduct($this->a, ['name' => 'Ekstra', 'price_minor' => 2000]);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->json('order.id');
        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $corba->id, 'qty' => 1])->assertCreated();
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $pide->id, 'qty' => 1])->assertCreated();
        $pideItem = collect($res->json('order.items'))->firstWhere('name', 'Pide');

        // Pide ayrı hesaba bölünür (split — is_split_child=true, tek-adisyon
        // kuralının BİLİNÇLİ istisnası; bkz. OrderService::splitByItems).
        $split = $this->postJson("/api/v1/orders/{$orderId}/split", [
            'mode' => 'items', 'item_ids' => [$pideItem['id']],
        ])->assertOk();
        $splitOrderId = $split->json('new_order.id');

        $this->assertTrue(Order::withoutTenancy()->find($splitOrderId)->is_split_child);
        $this->assertFalse(Order::withoutTenancy()->find($orderId)->is_split_child);

        // Ana adisyon (çorba) ödenip kapanır — split parçası hâlâ açık.
        $this->postJson("/api/v1/orders/{$orderId}/pay", ['amount_minor' => 5000, 'method' => 'cash'])->assertOk();
        $this->assertSame('paid', Order::withoutTenancy()->find($orderId)->status);
        $this->assertTrue(Order::withoutTenancy()->find($splitOrderId)->statusEnum()->isOpen());

        // Masadaki tek KALAN açık adisyon split parçası → yeni "aç" isteği
        // ona eklenir, üçüncü bir adisyon AÇILMAZ.
        $reOpen = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertOk();
        $this->assertSame($splitOrderId, $reOpen->json('order.id'));

        $this->postJson("/api/v1/orders/{$splitOrderId}/items", ['product_id' => $ekstra->id, 'qty' => 1])->assertCreated();

        // Masada toplam 2 adisyon satırı var: biri 'paid' (ana), biri açık
        // (split parçası) — üçüncüsü hiç oluşmadı.
        $this->assertSame(2, Order::withoutTenancy()->where('table_id', $table->id)->count());
    }
}
