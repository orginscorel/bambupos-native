<?php

namespace Tests\Concerns;

use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\Warehouse;
use App\Modules\Inventory\Services\RecipeService;
use App\Modules\Inventory\Services\StockLedger;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Stok testleri yardımcıları (InteractsWithTenancy ile birlikte).
 * Miktarlar milli (ana birim ×1000), para kuruş.
 */
trait InteractsWithInventory
{
    /** @param array{tenant: Tenant, branch?: mixed} $ctx */
    protected function makeWarehouse(array $ctx, array $attrs = []): Warehouse
    {
        return $this->asTenant($ctx['tenant'], function () use ($ctx, $attrs): Warehouse {
            $warehouse = new Warehouse(array_merge([
                'name' => 'Depo '.fake()->unique()->numerify('###'),
                'type' => 'main',
                'branch_id' => isset($ctx['branch']) ? $ctx['branch']->id : null,
                'is_default' => true,
                'is_active' => true,
            ], $attrs));
            $warehouse->save();

            return $warehouse;
        });
    }

    /** @param array{tenant: Tenant} $ctx */
    protected function makeStockItem(array $ctx, array $attrs = []): StockItem
    {
        return $this->asTenant($ctx['tenant'], function () use ($attrs): StockItem {
            $item = new StockItem(array_merge([
                'name' => 'Kalem '.fake()->unique()->numerify('#####'),
                'base_unit' => 'kg',
                'sub_unit' => 'g',
                'sub_unit_factor' => 1000,
                'is_active' => true,
            ], $attrs));
            $item->save();

            return $item;
        });
    }

    /** Alış hareketiyle stok yükler (defter üzerinden — tek kapı). */
    protected function seedStock(StockItem $item, Warehouse $warehouse, int $qtyMilli, int $unitCostMinor, ?User $user = null): void
    {
        app(StockLedger::class)->record([
            'type' => MovementType::Purchase,
            'item' => $item,
            'warehouse' => $warehouse,
            'qty_milli' => $qtyMilli,
            'tenant_id' => (int) $item->tenant_id,
            'unit_cost_minor' => $unitCostMinor,
            'description' => 'Test alışı',
            'user' => $user,
        ]);
    }

    /**
     * @param array{tenant: Tenant} $ctx
     * @param array<int, array{item_id: int, qty_milli: int, waste_percent?: float, warehouse_id?: int|null}> $lines
     */
    protected function makeRecipe(array $ctx, array $target, array $lines): \App\Modules\Inventory\Models\Recipe
    {
        return app(RecipeService::class)->saveVersion((int) $ctx['tenant']->id, $target + ['lines' => $lines], null);
    }

    protected function onHandMilli(StockItem $item, Warehouse $warehouse): int
    {
        return (int) \App\Modules\Inventory\Models\StockLevel::withoutTenancy()
            ->where('warehouse_id', $warehouse->getKey())
            ->where('item_id', $item->getKey())
            ->value('qty_milli');
    }
}
