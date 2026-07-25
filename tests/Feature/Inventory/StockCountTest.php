<?php

namespace Tests\Feature\Inventory;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockMovement;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\InteractsWithInventory;
use Tests\Concerns\InteractsWithTenancy;
use Tests\TestCase;

/**
 * SAYIM: kör giriş (beklenen gizli) → gönderim (fark) → onay (count_adjust).
 */
class StockCountTest extends TestCase
{
    use InteractsWithInventory, InteractsWithTenancy, RefreshDatabase;

    private array $a;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seedPermissions();
        $this->a = $this->makeTenantWithUser();
        $this->actingAs($this->a['user']);
    }

    public function test_kor_sayim_akisi_fark_ve_defter_kaydi(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a, ['name' => 'Sayılan Malzeme']);
        $this->seedStock($item, $warehouse, 10_000, 1_000); // beklenen 10 kg

        $countId = $this->postJson('/api/v1/inventory/counts', ['warehouse_id' => $warehouse->id])
            ->assertCreated()->json('count.id');

        // Sayan 8,4 kg girer.
        $this->putJson("/api/v1/inventory/counts/{$countId}/lines", [
            'lines' => [['item_id' => $item->id, 'counted_qty' => '8,4']],
        ])->assertOk();

        // KÖR: taslakta beklenen/fark yanıtta YOK.
        $draft = $this->getJson("/api/v1/inventory/counts/{$countId}")->assertOk()->json('count');
        $this->assertSame('draft', $draft['status']);
        $this->assertNull($draft['lines'][0]['expected_qty']);
        $this->assertNull($draft['lines'][0]['diff_qty']);

        // Gönderim: beklenen snapshot + fark = -1,6 kg.
        $submitted = $this->postJson("/api/v1/inventory/counts/{$countId}/submit")->assertOk()->json('count');
        $this->assertSame('submitted', $submitted['status']);
        $this->assertSame(-1_600, (int) $submitted['lines'][0]['diff_milli']);

        // Onay: count_adjust defteri + seviye düzeltmesi.
        $this->postJson("/api/v1/inventory/counts/{$countId}/approve")->assertOk();

        $this->assertSame(8_400, $this->onHandMilli($item, $warehouse));

        $adjust = StockMovement::withoutTenancy()
            ->where('type', MovementType::CountAdjust->value)
            ->where('ref_type', 'count')->where('ref_id', $countId)
            ->firstOrFail();

        $this->assertSame(-1_600, (int) $adjust->qty_milli);
    }

    public function test_sayim_onayi_stock_adjust_ister(): void
    {
        $warehouse = $this->makeWarehouse($this->a);
        $item = $this->makeStockItem($this->a);
        $this->seedStock($item, $warehouse, 5_000, 100);

        $countId = $this->postJson('/api/v1/inventory/counts', ['warehouse_id' => $warehouse->id])
            ->assertCreated()->json('count.id');
        $this->putJson("/api/v1/inventory/counts/{$countId}/lines", [
            'lines' => [['item_id' => $item->id, 'counted_qty' => '4']],
        ])->assertOk();
        $this->postJson("/api/v1/inventory/counts/{$countId}/submit")->assertOk();

        // stock.view'lu kullanıcı onaylayamaz.
        $viewer = \App\Modules\Identity\Models\User::factory()->create([
            'tenant_id' => $this->a['tenant']->id,
            'branch_id' => $this->a['branch']->id,
        ]);
        $role = \App\Modules\Identity\Models\Role::factory()->create(['tenant_id' => $this->a['tenant']->id]);
        $role->permissions()->sync(
            \App\Modules\Identity\Models\Permission::query()->where('key', 'stock.view')->pluck('id')->all()
        );
        $viewer->roles()->sync([$role->id]);

        $this->actingAs($viewer)
            ->postJson("/api/v1/inventory/counts/{$countId}/approve")
            ->assertForbidden();

        $this->assertSame(5_000, $this->onHandMilli($item, $warehouse)); // stok değişmedi
    }
}
