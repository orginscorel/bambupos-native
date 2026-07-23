<?php

namespace Database\Factories;

use App\Modules\Reservations\Models\WaitlistEntry;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<WaitlistEntry> */
class WaitlistEntryFactory extends Factory
{
    protected $model = WaitlistEntry::class;

    public function definition(): array
    {
        return [
            'customer_name' => fake()->name(),
            'customer_phone' => '05'.fake()->numerify('#########'),
            'party_size' => 2,
            'status' => 'waiting',
            'source' => 'panel',
        ];
    }
}
