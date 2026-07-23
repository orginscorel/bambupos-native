<?php

namespace Database\Factories;

use App\Modules\Receivables\Models\Receivable;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Receivable>
 */
class ReceivableFactory extends Factory
{
    protected $model = Receivable::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'name' => fake()->name(),
            'phone' => fake()->phoneNumber(),
            'balance_minor' => 0,
            'is_active' => true,
        ];
    }
}
