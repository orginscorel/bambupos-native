<?php

namespace Tests\Concerns;

use App\Modules\Catalog\Models\Option;
use App\Modules\Catalog\Models\OptionGroup;
use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductVariant;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Tenant;

/**
 * Sipariş testleri için katalog/masa kurulum yardımcıları.
 * (InteractsWithTenancy ile birlikte kullanılır.)
 */
trait InteractsWithOrders
{
    /** @param array{tenant: Tenant, branch: mixed} $ctx */
    protected function makeTable(array $ctx, array $attrs = []): Table
    {
        return Table::factory()->create(array_merge([
            'tenant_id' => $ctx['tenant']->id,
            'branch_id' => $ctx['branch']->id,
        ], $attrs));
    }

    /** @param array{tenant: Tenant} $ctx */
    protected function makeProduct(array $ctx, array $attrs = []): Product
    {
        return Product::factory()->create(array_merge([
            'tenant_id' => $ctx['tenant']->id,
            'price_minor' => 10000, // 100,00 TL
            'tax_rate' => 10.00,
        ], $attrs));
    }

    /**
     * Ürüne bağlı seçenek grubu + seçenekler.
     *
     * @param  array{tenant: Tenant}  $ctx
     * @param  array<int, array{name: string, price_minor: int}>  $options
     */
    protected function attachOptionGroup(array $ctx, Product $product, array $groupAttrs, array $options): OptionGroup
    {
        return $this->asTenant($ctx['tenant'], function () use ($product, $groupAttrs, $options): OptionGroup {
            $group = OptionGroup::query()->create(array_merge([
                'name' => 'Seçenekler',
                'selection_type' => 'multiple',
                'is_required' => false,
                'min_select' => 0,
            ], $groupAttrs));

            foreach ($options as $opt) {
                Option::query()->create([
                    'option_group_id' => $group->id,
                    'name' => $opt['name'],
                    'price_minor' => $opt['price_minor'],
                    'is_active' => true,
                ]);
            }

            $product->optionGroups()->attach($group->id, ['sort_order' => 0]);

            return $group->fresh('options');
        });
    }

    /** @param array{tenant: Tenant} $ctx */
    protected function attachVariant(array $ctx, Product $product, string $name, int $priceMinor): ProductVariant
    {
        return $this->asTenant($ctx['tenant'], fn (): ProductVariant => ProductVariant::query()->create([
            'product_id' => $product->id,
            'name' => $name,
            'price_minor' => $priceMinor,
            'is_active' => true,
        ]));
    }
}
