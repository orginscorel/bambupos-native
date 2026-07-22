<?php

namespace Database\Factories;

use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Order>
 */
class OrderFactory extends Factory
{
    protected $model = Order::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'branch_id' => Branch::factory(),
            'status' => 'open',
            'total_minor' => fake()->numberBetween(5000, 250000), // ADR-007 kuruş
            'currency' => 'TRY',
        ];
    }
}
