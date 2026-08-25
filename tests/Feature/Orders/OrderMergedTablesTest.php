<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\OrderLinkedTable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * BİRLEŞİK MASALAR: kalabalık grup birden çok masaya oturur.
 *
 * Birleştirme kaynak adisyonu iptal ediyordu ve kaynak masa panoda BOŞ
 * görünüyordu — garson üstüne yeni müşteri oturtabilirdi. Artık masa
 * adisyona BAĞLI kalır; pano "birleşik" gösterir, kasa tek hesapta toplar.
 */
class OrderMergedTablesTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    public function test_birlestirmede_kaynak_masa_adisyona_bagli_kalir(): void
    {
        $this->seedPermissions();
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $t1 = $this->makeTable($a);
        $t2 = $this->makeTable($a);
        $product = $this->makeProduct($a, ['price_minor' => 5000]);

        $o1 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t1->id])->json('order.id');
        $o2 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t2->id])->json('order.id');

        $this->postJson("/api/v1/orders/{$o1}/items", ['product_id' => $product->id, 'qty' => 1])->assertCreated();
        $this->postJson("/api/v1/orders/{$o2}/items", ['product_id' => $product->id, 'qty' => 2])->assertCreated();

        // 2 numaralı adisyon 1'e birleşir
        $res = $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertOk();

        // Kalemler tek adisyonda toplandı
        $this->assertSame(15000, $res->json('order.total_minor'));

        // Kaynak masa BAĞLI (boş değil)
        $this->assertDatabaseHas('order_linked_tables', ['order_id' => $o1, 'table_id' => $t2->id]);

        // Adisyon özeti birleşik masayı bildiriyor
        $names = $this->getJson("/api/v1/orders/{$o1}")->json('order.linked_table_names');
        $this->assertSame([$t2->name], $names);
    }

    public function test_panoda_bagli_masa_bos_gorunmez(): void
    {
        $this->seedPermissions();
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $t1 = $this->makeTable($a);
        $t2 = $this->makeTable($a);
        $product = $this->makeProduct($a, ['price_minor' => 5000]);

        $o1 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t1->id])->json('order.id');
        $o2 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t2->id])->json('order.id');
        $this->postJson("/api/v1/orders/{$o2}/items", ['product_id' => $product->id, 'qty' => 1])->assertCreated();

        $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertOk();

        $board = $this->getJson('/api/v1/orders/board')->assertOk()->json('tables');
        $linked = collect($board)->firstWhere('id', $t2->id);

        $this->assertNotNull($linked);
        $this->assertSame([], $linked['orders'], 'Bağlı masada AYRI adisyon görünmemeli (çift sayım olmaz).');
        $this->assertNotNull($linked['linked_to'], 'Bağlı masa boş görünmemeli.');
        $this->assertSame($o1, $linked['linked_to']['order_id']);
    }

    public function test_ucuncu_masa_da_ayni_adisyona_baglanir(): void
    {
        $this->seedPermissions();
        $a = $this->makeTenantWithUser();
        $this->actingAs($a['user']);

        $t1 = $this->makeTable($a);
        $t2 = $this->makeTable($a);
        $t3 = $this->makeTable($a);

        $o1 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t1->id])->json('order.id');
        $o2 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t2->id])->json('order.id');
        $o3 = (int) $this->postJson('/api/v1/orders', ['branch_id' => $a['branch']->id, 'channel' => 'table', 'table_id' => $t3->id])->json('order.id');

        $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o2])->assertOk();
        $this->postJson("/api/v1/orders/{$o1}/merge", ['source_order_id' => $o3])->assertOk();

        $this->assertSame(2, OrderLinkedTable::withoutTenancy()->where('order_id', $o1)->count());
    }
}
