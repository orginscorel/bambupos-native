<?php

namespace Database\Factories;

use App\Modules\Catalog\Models\Product;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Product>
 */
class ProductFactory extends Factory
{
    protected $model = Product::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'name' => fake()->words(2, true),
            'sku' => Str::upper(Str::random(8)),
            'price_minor' => fake()->numberBetween(1000, 50000), // ADR-007 kuruş
            'currency' => 'TRY',
            'is_active' => true,
        ];
    }
}
