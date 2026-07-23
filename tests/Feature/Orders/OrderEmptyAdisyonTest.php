<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\Order;
use App\Modules\Tables\Models\Table;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * KURAL (hata kaydı 2026-07, "Teras 1 takılı kaldı"): açık adisyonun TÜM
 * kalemleri silinir/iptal edilirse adisyon otomatik kapanır (denetim
 * kaydıyla) ve masa durumu yeniden türetilir → başka açık adisyon yoksa
 * masa Boş'a döner. Rezerve/Kullanım dışı masa ezilmez.
 */
class OrderEmptyAdisyonTest extends TestCase
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

    /** @return array{orderId: int, itemIds: array<int, int>} */
    private function openOrderWithItems(Table $table, int $itemCount = 1): array
    {
        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id,
            'channel' => 'table',
            'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $itemIds = [];

        for ($i = 0; $i < $itemCount; $i++) {
            $product = $this->makeProduct($this->a, ['name' => "Ürün {$orderId}-{$i}"]);
            $res = $this->postJson("/api/v1/orders/{$orderId}/items", [
                'product_id' => $product->id, 'qty' => 1,
            ])->assertCreated();
            $itemIds[] = collect($res->json('order.items'))->firstWhere('name', $product->name)['id'];
        }

        return ['orderId' => $orderId, 'itemIds' => $itemIds];
    }

    public function test_tum_kalemler_silinince_adisyon_otomatik_kapanir_ve_masa_bosalir(): void
    {
        $table = $this->makeTable($this->a);
        ['orderId' => $orderId, 'itemIds' => $itemIds] = $this->openOrderWithItems($table, 2);

        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);

        // İlk kalem silindi → adisyon hâlâ açık, masa dolu
        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$itemIds[0]}")->assertOk();
        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);

        // Son kalem de silindi → adisyon otomatik kapanır, masa Boş'a döner
        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$itemIds[1]}")->assertOk();

        $order = Order::withoutTenancy()->find($orderId);
        $this->assertSame('cancelled', $order->status);
        $this->assertNotNull($order->cancelled_at);
        $this->assertSame('Tüm kalemler kaldırıldı — adisyon otomatik kapatıldı', $order->cancel_reason);
        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);

        // İz: order_events + audit_logs
        $this->assertDatabaseHas('order_events', ['order_id' => $orderId, 'type' => 'auto_closed_empty']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'orders.auto_closed_empty', 'entity_id' => $orderId]);
    }

    public function test_tum_kalemler_iptal_edilince_de_masa_bosalir(): void
    {
        $table = $this->makeTable($this->a);
        ['orderId' => $orderId, 'itemIds' => $itemIds] = $this->openOrderWithItems($table, 1);

        $this->postJson("/api/v1/orders/{$orderId}/items/{$itemIds[0]}/cancel", ['reason' => 'müşteri vazgeçti'])
            ->assertOk();

        $this->assertSame('cancelled', Order::withoutTenancy()->find($orderId)->status);
        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);
    }

    /**
     * KURAL DEĞİŞİKLİĞİ (Adisyon-Cari, 2026-07-23): "masada birden fazla
     * açık adisyon olamaz" — bu test ÖNCEDEN aynı masada 2 AYRI açık
     * adisyon açılabildiğini varsayıyordu ("biri boşalsa da diğeri masayı
     * dolu tutar"). O senaryo artık MÜMKÜN DEĞİL: aynı masaya ikinci
     * "adisyon aç" isteği YENİ adisyon YARATMAZ — var olana idempotent
     * biçimde döner (bkz. OrderService::open + orders_tenant_table_open_slot_unique).
     * Test artık TAM O YENİ DAVRANIŞI + adisyon boşalma kuralının tek
     * adisyon üzerinde hâlâ doğru çalıştığını doğruluyor.
     */
    public function test_masada_tek_acik_adisyon_ikinci_acma_istegi_ayni_adisyona_eklenir(): void
    {
        $table = $this->makeTable($this->a);

        $first = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated();
        $orderId = $first->json('order.id');

        // Aynı masaya ikinci "aç" isteği (garson ikinci kez tıkladı / iki
        // terminalden aynı anda geldi): YENİ adisyon açılmaz, 200 ile var
        // olanı döner (201 DEĞİL — yeni kaynak oluşmadı).
        $second = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertOk();
        $this->assertSame($orderId, $second->json('order.id'));

        $this->assertSame(1, Order::withoutTenancy()->where('table_id', $table->id)
            ->whereNotIn('status', ['paid', 'cancelled', 'refunded', 'debt_transferred'])
            ->count());

        $p1 = $this->makeProduct($this->a, ['name' => 'Kalem A']);
        $p2 = $this->makeProduct($this->a, ['name' => 'Kalem B']);
        $item1 = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p1->id, 'qty' => 1])
            ->assertCreated()->json('order.items.0.id');
        $res = $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $p2->id, 'qty' => 1])->assertCreated();
        $item2 = collect($res->json('order.items'))->firstWhere('name', 'Kalem B')['id'];

        // Bir kalem kaldırılınca adisyon hâlâ açık, masa dolu.
        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$item1}")->assertOk();
        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);

        // Son kalem de kaldırılınca adisyon otomatik kapanır, masa boşalır.
        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$item2}")->assertOk();
        $this->assertSame('cancelled', Order::withoutTenancy()->find($orderId)->status);
        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_rezerve_masa_adisyon_bosalinca_ezilmez(): void
    {
        $table = $this->makeTable($this->a);
        ['orderId' => $orderId, 'itemIds' => $itemIds] = $this->openOrderWithItems($table, 1);

        // Personel masayı rezerve işaretledi (operasyon-dışı durum)
        Table::withoutTenancy()->whereKey($table->id)->update(['status' => 'reserved']);

        $this->deleteJson("/api/v1/orders/{$orderId}/items/{$itemIds[0]}")->assertOk();

        $this->assertSame('cancelled', Order::withoutTenancy()->find($orderId)->status);
        $this->assertSame('reserved', Table::withoutTenancy()->find($table->id)->status->value);
    }

    public function test_onarim_komutu_eski_bozuk_veriyi_duzeltir(): void
    {
        $table = $this->makeTable($this->a);
        ['orderId' => $orderId, 'itemIds' => $itemIds] = $this->openOrderWithItems($table, 1);

        // Kural öncesi bozuk durumu taklit et: kalem DB'den doğrudan silindi,
        // adisyon açık ve masa "Sipariş alındı" olarak takılı kaldı.
        \App\Modules\Orders\Models\OrderItem::withoutTenancy()->whereKey($itemIds[0])->delete();
        Order::withoutTenancy()->whereKey($orderId)->update(['created_at' => now()->subHour()]);
        $this->assertSame('order_taken', Table::withoutTenancy()->find($table->id)->status->value);

        $this->artisan('orders:repair-table-status')->assertSuccessful();

        $this->assertSame('cancelled', Order::withoutTenancy()->find($orderId)->status);
        $this->assertSame('available', Table::withoutTenancy()->find($table->id)->status->value);
    }
}
