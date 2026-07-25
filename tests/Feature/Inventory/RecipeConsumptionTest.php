<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Models\Warehouse;
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
 * REÇETE TÜKETİMİ DOĞRULUĞU (§17 madde 3+5): kalem `served` olunca reçete
 * deftere düşer; miktarlar milli-int, maliyetler kuruş-int — KAYIP YOK.
 */
class RecipeConsumptionTest extends TestCase
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

    /** Adisyon + kalem kurar, kalemi döndürür. */
    private function placeOrder(int $productId, int $qty): array
    {
        $table = $this->makeTable($this->a);

        $orderId = $this->postJson('/api/v1/orders', [
            'branch_id' => $this->a['branch']->id, 'channel' => 'table', 'table_id' => $table->id,
        ])->assertCreated()->json('order.id');

        $this->postJson("/api/v1/orders/{$orderId}/items", ['product_id' => $productId, 'qty' => $qty])->assertCreated();

        $order = Order::withoutTenancy()->findOrFail($orderId);
        $item = OrderItem::withoutTenancy()->where('order_id', $orderId)->firstOrFail();

        return [$order, $item];
    }

    private function serve(Order $order, OrderItem $item): void
    {
        $this->asTenant($this->a['tenant'], function () use ($order, $item): void {
            app(OrderService::class)->setItemStatus($order, $item, OrderItemStatus::Served, $this->a['user']);
        });
    }

    public function test_served_kalem_receteye_gore_dusulur_birim_ve_kurus_kaybi_yok(): void
    {
        $warehouse = $this->makeWarehouse($this->a);

        // 1 burger = 160 g kıyma + 1 adet ekmek + 20 g sos (alt birim dönüşümü dahil).
        $kiyma = $this->makeStockItem($this->a, ['name' => 'Dana Kıyma']);
        $ekmek = $this->makeStockItem($this->a, ['name' => 'Burger Ekmeği', 'base_unit' => 'adet', 'sub_unit' => null, 'sub_unit_factor' => null]);
        $sos = $this->makeStockItem($this->a, ['name' => 'Burger Sos']);

        $this->seedStock($kiyma, $warehouse, 10_000, 32_000);  // 10 kg × 320,00 TL/kg
        $this->seedStock($ekmek, $warehouse, 20_000, 500);     // 20 adet × 5,00 TL
        $this->seedStock($sos, $warehouse, 5_000, 8_000);      // 5 kg × 80,00 TL/kg

        $product = $this->makeProduct($this->a, ['name' => 'Burger']);

        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $kiyma->id, 'qty_milli' => 160],  // 160 g
            ['item_id' => $ekmek->id, 'qty_milli' => 1000], // 1 adet
            ['item_id' => $sos->id, 'qty_milli' => 20],     // 20 g
        ]);

        [$order, $item] = $this->placeOrder($product->id, 5);
        $this->serve($order, $item);

        // 5 porsiyon: kıyma 800 milli-kg, ekmek 5 adet, sos 100 milli-kg — TAM.
        $this->assertSame(10_000 - 800, $this->onHandMilli($kiyma, $warehouse));
        $this->assertSame(20_000 - 5_000, $this->onHandMilli($ekmek, $warehouse));
        $this->assertSame(5_000 - 100, $this->onHandMilli($sos, $warehouse));

        $movements = StockMovement::withoutTenancy()
            ->where('ref_type', 'order_item')->where('ref_id', $item->id)->get();

        $this->assertCount(3, $movements);
        $this->assertTrue($movements->every(fn ($m) => $m->type === MovementType::RecipeConsumption->value));

        // Maliyet: 0,8 kg × 32000 kuruş = 25600 kuruş — kuruş kaybı yok.
        $kiymaMove = $movements->firstWhere('item_id', $kiyma->id);
        $this->assertSame(-800, (int) $kiymaMove->qty_milli);
        $this->assertSame(25_600, (int) $kiymaMove->total_cost_minor);

        // DEĞİŞMEZ: defter toplamı == anlık seviye (defter tek doğruluk kaynağı).
        $ledger = app(StockLedger::class);
        $this->assertSame($this->onHandMilli($kiyma, $warehouse), $ledger->ledgerBalance($warehouse->id, $kiyma->id));
        $this->assertSame($this->onHandMilli($ekmek, $warehouse), $ledger->ledgerBalance($warehouse->id, $ekmek->id));
    }

    public function test_served_sonrasi_odeme_cifte_dusum_yapmaz_idempotent(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $kiyma = $this->makeStockItem($this->a);
        $this->seedStock($kiyma, $warehouse, 10_000, 10_000);

        $product = $this->makeProduct($this->a, ['price_minor' => 10_000]);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $kiyma->id, 'qty_milli' => 200],
        ]);

        [$order, $item] = $this->placeOrder($product->id, 2);
        $this->serve($order, $item);

        $this->assertSame(10_000 - 400, $this->onHandMilli($kiyma, $warehouse));

        // Tam ödeme → sipariş paid olur → güvenlik ağı tetiklenir ama İKİNCİ düşüm OLMAZ.
        $total = (int) Order::withoutTenancy()->find($order->id)->total_minor;
        $this->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'cash', 'amount_minor' => $total])->assertCreated();

        $this->assertSame('paid', Order::withoutTenancy()->find($order->id)->status);
        $this->assertSame(10_000 - 400, $this->onHandMilli($kiyma, $warehouse)); // değişmedi
        $this->assertSame(1, StockMovement::withoutTenancy()->where('ref_type', 'order_item')->where('ref_id', $item->id)->count());
    }

    public function test_servis_isaretlenmeden_odenen_adisyon_odemede_dusulur(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 5_000, 1_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $malzeme->id, 'qty_milli' => 500],
        ]);

        [$order, $item] = $this->placeOrder($product->id, 1);

        $total = (int) Order::withoutTenancy()->find($order->id)->total_minor;
        $this->postJson("/api/v1/orders/{$order->id}/payments", ['method' => 'cash', 'amount_minor' => $total])->assertCreated();

        $this->assertSame(5_000 - 500, $this->onHandMilli($malzeme, $warehouse));
    }

    public function test_ikram_kalemi_ikram_tuketimi_turuyle_dusuler(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 2_000, 1_000);

        $product = $this->makeProduct($this->a);
        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $malzeme->id, 'qty_milli' => 100],
        ]);

        [$order, $item] = $this->placeOrder($product->id, 1);

        $this->asTenant($this->a['tenant'], function () use ($order, $item): void {
            app(OrderService::class)->compItem($order, $item, 'Müşteri memnuniyeti', $this->a['user']);
        });

        $this->serve(Order::withoutTenancy()->find($order->id), $item);

        $move = StockMovement::withoutTenancy()->where('ref_type', 'order_item')->where('ref_id', $item->id)->firstOrFail();
        $this->assertSame(MovementType::CompConsumption->value, $move->type); // §17.4 ikram-tüketimi
        $this->assertSame(2_000 - 100, $this->onHandMilli($malzeme, $warehouse));
    }

    public function test_sube_ozel_recete_genel_receteyi_ezer(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 10_000, 1_000);

        $product = $this->makeProduct($this->a);

        // Genel reçete 100 g; ŞUBE reçetesi 120 g — sipariş şubeden → 120 düşer.
        $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 100]]);
        $this->makeRecipe($this->a, ['product_id' => $product->id, 'branch_id' => $this->a['branch']->id], [['item_id' => $malzeme->id, 'qty_milli' => 120]]);

        [$order, $item] = $this->placeOrder($product->id, 1);
        $this->serve($order, $item);

        $this->assertSame(10_000 - 120, $this->onHandMilli($malzeme, $warehouse));
    }

    public function test_fire_orani_tuketime_eklenir(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 10_000, 1_000);

        $product = $this->makeProduct($this->a);

        // 160 g + %5 satır firesi = 168 g / porsiyon.
        $this->makeRecipe($this->a, ['product_id' => $product->id], [
            ['item_id' => $malzeme->id, 'qty_milli' => 160, 'waste_percent' => 5.0],
        ]);

        [$order, $item] = $this->placeOrder($product->id, 1);
        $this->serve($order, $item);

        $this->assertSame(10_000 - 168, $this->onHandMilli($malzeme, $warehouse));
    }

    public function test_recetesiz_urun_hareket_yazmaz_ve_akisi_bozmaz(): void
    {
        $product = $this->makeProduct($this->a);

        [$order, $item] = $this->placeOrder($product->id, 3);
        $this->serve($order, $item);

        $this->assertSame('served', OrderItem::withoutTenancy()->find($item->id)->status);
        $this->assertSame(0, StockMovement::withoutTenancy()->where('ref_type', 'order_item')->count());
    }

    public function test_recete_versiyonlama_eski_surum_pasif_yeni_surum_gecerli(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $malzeme = $this->makeStockItem($this->a);
        $this->seedStock($malzeme, $warehouse, 10_000, 1_000);

        $product = $this->makeProduct($this->a);

        $v1 = $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 100]]);
        $v2 = $this->makeRecipe($this->a, ['product_id' => $product->id], [['item_id' => $malzeme->id, 'qty_milli' => 250]]);

        $this->assertSame(1, (int) $v1->version);
        $this->assertSame(2, (int) $v2->version);
        $this->assertFalse((bool) $v1->fresh()->is_active);
        $this->assertTrue((bool) $v2->fresh()->is_active);

        [$order, $item] = $this->placeOrder($product->id, 1);
        $this->serve($order, $item);

        $this->assertSame(10_000 - 250, $this->onHandMilli($malzeme, $warehouse)); // yeni sürüm
    }

    public function test_yari_mamul_uretimi_bileseni_dusurur_hedefi_artirir(): void
    {
        $warehouse = $this->makeWarehouse($this->a);

        $domates = $this->makeStockItem($this->a, ['name' => 'Domates']);
        $sos = $this->makeStockItem($this->a, ['name' => 'Ev Sosu', 'is_semi_finished' => true]);
        $this->seedStock($domates, $warehouse, 20_000, 2_000); // 20 kg × 20 TL

        // 1 kg sos = 2 kg domates.
        $this->makeRecipe($this->a, ['item_id' => $sos->id, 'yield_qty_milli' => 1000], [
            ['item_id' => $domates->id, 'qty_milli' => 2000],
        ]);

        $this->asTenant($this->a['tenant'], function () use ($sos, $warehouse): void {
            app(ConsumptionService::class)->produce($sos->fresh(), 5_000, Warehouse::withoutTenancy()->find($warehouse->id), $this->a['user']);
        });

        $this->assertSame(20_000 - 10_000, $this->onHandMilli($domates, $warehouse)); // 5 kg sos → 10 kg domates
        $this->assertSame(5_000, $this->onHandMilli($sos, $warehouse));

        // Üretilen sosun birim maliyeti: 10 kg × 2000 kuruş = 20000 kuruş / 5 kg = 4000 kuruş/kg.
        $this->assertSame(4_000, (int) $sos->fresh()->avg_cost_minor);
    }
}
