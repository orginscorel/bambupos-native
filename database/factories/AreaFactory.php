<?php

namespace Database\Factories;

use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Venue\Enums\AreaType;
use App\Modules\Venue\Models\Area;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Area>
 */
class AreaFactory extends Factory
{
    protected $model = Area::class;

    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'branch_id' => Branch::factory(),
            'floor_id' => null,
            'name' => 'Alan '.fake()->unique()->numberBetween(1, 90000),
            'type' => AreaType::Indoor->value,
            'sort_order' => 0,
            'is_active' => true,
        ];
    }
}
