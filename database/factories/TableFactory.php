<?php

namespace Database\Factories;

use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Table>
 */
class TableFactory extends Factory
{
    protected $model = Table::class;

    public function definition(): array
    {
        $number = fake()->unique()->numberBetween(1, 900000);

        return [
            'tenant_id' => Tenant::factory(),
            'branch_id' => Branch::factory(),
            'name' => 'Masa '.$number,
            'number' => $number,
            'capacity' => 4,
            'shape' => 'square',
            'status' => 'available',
            'is_joinable' => true,
            'qr_token' => Table::generateQrToken(),
            'is_active' => true,
        ];
    }
}
