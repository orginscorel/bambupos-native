<?php

namespace Database\Factories;

use App\Modules\Reservations\Models\Reservation;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Reservation> */
class ReservationFactory extends Factory
{
    protected $model = Reservation::class;

    public function definition(): array
    {
        return [
            'customer_name' => fake()->name(),
            'customer_phone' => '05'.fake()->numerify('#########'),
            'customer_email' => fake()->safeEmail(),
            'reserved_at' => now()->addDay()->setTime(19, 0),
            'duration_minutes' => 120,
            'buffer_minutes' => 15,
            'party_size' => 2,
            'deposit_minor' => 0,
            'deposit_status' => 'none',
            'source' => 'panel',
            'status' => 'confirmed',
        ];
    }
}
