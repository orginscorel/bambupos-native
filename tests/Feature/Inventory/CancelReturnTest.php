<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Services\ConsumptionService;
use App\Modules\Inventory\Services\StockLedger;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use App\Modules\Orders\Services\OrderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithOrders;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * İPTAL → İADE (§17 madde 4): iptal edilen kalemin reçete tüketimi stoğa
 * GERİ EKLENİR; iade satırı SEBEP taşır; idempotenttir.
 */
class CancelReturnTest extends TestCase
{
    use InteractsWithInventory, InteractsWithOrders, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    private function placeOrder(int $productId, int $qty): array
    {
        $table = $this->makeTable($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $productId, 'qty' => $qty])->assertCreated();

        return [
            Order::withoutTenancy()->findOrFail($orderId),
            OrderItem::withoutTenancy()->where('order_id', $orderId)->firstOrFail(),
        ];
    }

    private function serve(Order $order, OrderItem $item): void
    {
        $this->asTenant($this->a['tenant'], function () use ($order, $item): void {
            app(OrderService::class)->setItemStatus($order, $item, OrderItemStatus::Served, $this->a['user']);
        });
    }

    public function test_tuketilen_kalem_iptalinde_stok_iade_edilir_sebep_yazilir(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $kiyma = $this->makeStockItem($this->a, ['name' => 'Dana Kıyma']);
        $this->seedStock($kiyma, $warehouse, 10_000, 32_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $kiyma->id, 'qty_milli' => 200],
        ]);

        [$order, $item] = $this->placeOrder($product->id, 3);
        $this->serve($order, $item);

        $this->assertSame(10_000 - 600, $this->onHandMilli($kiyma, $warehouse)); // 3 × 200

        // Kalem yanlış girildi → iade (sebep zorunlu).
        $fresh = OrderItem::withoutTenancy()->find($item->id);
        $fresh->cancel_reason = 'Yanlış masaya girildi';

        $this->asTenant($this->a['tenant'], function () use ($fresh): void {
            app(ConsumptionService::class)->revertOrderItem($fresh);
        });

        // Stok başa döndü.
        $this->assertSame(10_000, $this->onHandMilli($kiyma, $warehouse));

        $return = StockMovement::withoutTenancy()
            ->where('ref_type', 'order_item_return')->where('ref_id', $item->id)->firstOrFail();

        $this->assertSame(200 * 3, (int) $return->qty_milli);            // + (stoğa girer)
        $this->assertStringContainsString('Yanlış masaya girildi', (string) $return->description);

        // Defter tek doğruluk kaynağı: toplam == seviye.
        $this->assertSame(
            $this->onHandMilli($kiyma, $warehouse),
            app(StockLedger::class)->ledgerBalance($warehouse->id, $kiyma->id),
        );
    }

    public function test_iade_idempotenttir_ikinci_cagri_tekrar_eklemez(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 5_000, 1_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 100]]);

        [$order, $item] = $this->placeOrder($product->id, 1);
        $this->serve($order, $item);

        $fresh = OrderItem::withoutTenancy()->find($item->id);
        $fresh->cancel_reason = 'Test';

        $this->asTenant($this->a['tenant'], function () use ($fresh): void {
            app(ConsumptionService::class)->revertOrderItem($fresh);
            app(ConsumptionService::class)->revertOrderItem($fresh); // ikinci kez — no-op
        });

        $this->assertSame(5_000, $this->onHandMilli($malzeme, $warehouse)); // tam iade, çift değil
        $this->assertSame(1, StockMovement::withoutTenancy()
            ->where('ref_type', 'order_item_return')->where('ref_id', $item->id)->count());
    }

    public function test_dusulmemis_kalem_iadesi_hareket_yazmaz(): void
    {
        // Reçetesi olmayan / hiç tüketilmemiş kalem → iade edilecek bir şey yok.
        $product = $this->makeProduct($this->a);
        [, $item] = $this->placeOrder($product->id, 1);

        $fresh = OrderItem::withoutTenancy()->find($item->id);
        $fresh->cancel_reason = 'Boş';

        $this->asTenant($this->a['tenant'], function () use ($fresh): void {
            $moves = app(ConsumptionService::class)->revertOrderItem($fresh);
            $this->assertSame([], $moves);
        });

        $this->assertSame(0, StockMovement::withoutTenancy()->where('ref_type', 'order_item_return')->count());
    }

    public function test_sebepsiz_iptalde_guvenli_metin_yazilir(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 5_000, 1_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 100]]);

        [$order, $item] = $this->placeOrder($product->id, 1);
        $this->serve($order, $item);

        $fresh = OrderItem::withoutTenancy()->find($item->id); // cancel_reason boş

        $this->asTenant($this->a['tenant'], function () use ($fresh): void {
            app(ConsumptionService::class)->revertOrderItem($fresh);
        });

        $return = StockMovement::withoutTenancy()
            ->where('ref_type', 'order_item_return')->where('ref_id', $item->id)->firstOrFail();

        $this->assertStringContainsString('sebep belirtilmedi', (string) $return->description);
    }

    public function test_model_olayi_status_cancelled_olunca_iade_tetiklenir(): void
    {
        // Sipariş↔stok köprüsü: OrderItem status → cancelled olayında iade.
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 5_000, 1_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 300]]);

        // Servis işaretlenmeden ödenir → güvenlik ağı tüketir (kalem 'placed' kalır).
        [$order, $item] = $this->placeOrder($product->id, 1);
        $total = (int) Order::withoutTenancy()->find($order->id)->total_minor;
        $this->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'cash', 'amount_minor' => $total])->assertCreated();

        $this->assertSame(5_000 - 300, $this->onHandMilli($malzeme, $warehouse));

        // Kalem iptal edilir (placed → cancelled) → model olayı iade yazar.
        $this->asTenant($this->a['tenant'], function () use ($item): void {
            $row = OrderItem::withoutTenancy()->find($item->id);
            $row->cancel_reason = 'Müşteri vazgeçti';
            $row->status = OrderItemStatus::Cancelled->value;
            $row->save();
        });

        $this->assertSame(5_000, $this->onHandMilli($malzeme, $warehouse)); // iade edildi
        $this->assertSame(1, StockMovement::withoutTenancy()
            ->where('ref_type', 'order_item_return')->where('ref_id', $item->id)->count());
    }
}
