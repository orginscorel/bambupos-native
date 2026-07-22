<?php

namespace Tests\Feature\Orders;

use App\Modules\Orders\Models\Order;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * Kiracı izolasyonu (ADR-004): A kiracısı B'nin adisyonunu göremez,
 * değiştiremez; B'nin ürünü/masası A'nın adisyonuna sızamaz.
 */
class OrderIsolationTest extends TestCase
{
    use InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    private array $b;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->b = $this->makeTenantWithUser();
    }

    public function test_yabanci_adisyona_erisim_ve_mutasyon_404(): void
    {
        // B kendi adisyonunu açar
        $this->actingAs($this->b['user']);
        $bTable = $this->makeTable($this->b);
        $bProduct = $this->makeProduct($this->b);
        $bOrder = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->b['branch']->id, 'channel' => 'table', 'table_id' => $bTable->id,
        ])->json('order.id');
        $bItem = $this->postJson("/api/v1/orders/{$bOrder}/items", ['product_id' => $bProduct->id, 'qty' => 1])
            ->json('order.items.0.id');

        // A hiçbirine dokunamaz
        $this->actingAs($this->a['user']);
        $this->getJson("/api/v1/orders/{$bOrder}")->assertNotFound();
        $this->postJson("/api/v1/orders/{$bOrder}/items", ['product_id' => $bProduct->id, 'qty' => 1])->assertNotFound();
        $this->postJson("/api/v1/orders/{$bOrder}/cancel", ['reason' => 'sızma denemesi'])->assertNotFound();
        $this->putJson("/api/v1/orders/{$bOrder}/status", ['status' => 'preparing'])->assertNotFound();
        $this->postJson("/api/v1/orders/{$bOrder}/pay", ['amount_minor' => 100, 'method' => 'cash'])->assertNotFound();
        $this->get("/panel/siparisler/{$bOrder}")->assertNotFound();

        // Liste ve panoda B'nin verisi görünmez
        $ids = collect($this->getJson('/api/v1/orders')->json('orders.data'))->pluck('id');
        $this->assertFalse($ids->contains($bOrder));
        $this->assertSame([], $this->getJson('/api/v1/orders/board')->json('tables'));
    }

    public function test_yabanci_urun_masa_ve_adisyon_kendi_adisyonuma_sizamaz(): void
    {
        $this->actingAs($this->b['user']);
        $bProduct = $this->makeProduct($this->b);
        $bTable = $this->makeTable($this->b);
        $bOrder = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->b['branch']->id, 'channel' => 'table', 'table_id' => $bTable->id,
        ])->json('order.id');

        $this->actingAs($this->a['user']);
        $aTable = $this->makeTable($this->a);
        $aOrder = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $aTable->id,
        ])->json('order.id');

        // B'nin ürünü A'nın adisyonuna eklenemez
        $this->postJson("/api/v1/orders/{$aOrder}/items", ['product_id' => $bProduct->id, 'qty' => 1])
            ->assertUnprocessable();

        // B'nin masasına taşınamaz
        $this->postJson("/api/v1/orders/{$aOrder}/move", ['table_id' => $bTable->id])->assertUnprocessable();

        // B'nin adisyonuyla birleştirilemez (scoped sorgu bulamaz)
        $this->postJson("/api/v1/orders/{$aOrder}/merge", ['source_order_id' => $bOrder])->assertUnprocessable();

        // B'nin masası A'nın panosunda görünmez
        $tableIds = collect($this->getJson('/api/v1/orders/board')->json('tables'))->pluck('id');
        $this->assertFalse($tableIds->contains($bTable->id));

        // B'nin adisyonuna hiçbir şey yazılmadı
        $this->assertSame(0, Order::withoutTenancy()->find($bOrder)->items()->withoutGlobalScopes()->count());
    }
}
