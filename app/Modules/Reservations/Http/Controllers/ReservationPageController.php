<?php

namespace App\Modules\Reservations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reservations\Enums\DepositStatus;
use App\Modules\Reservations\Enums\ReservationSource;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Enums\WaitlistStatus;
use App\Modules\Reservations\Models\Reservation;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Panel Inertia sayfaları. Enum sözlükleri PHP enum'dan prop olarak gider
 * (tek kaynak; TS tarafında kopya tutulmaz — Venue ile aynı desen).
 */
class ReservationPageController extends Controller
{
    public function index(): Response
    {
        $this->authorize('viewAny', Reservation::class);

        return Inertia::render('Panel/Reservations/Index', $this->meta());
    }

    public function waitlist(): Response
    {
        $this->authorize('viewAny', Reservation::class);

        return Inertia::render('Panel/Reservations/Waitlist', $this->meta());
    }

    public function noShowReport(): Response
    {
        $this->authorize('viewAny', Reservation::class);

        return Inertia::render('Panel/Reservations/NoShowReport', $this->meta());
    }

    /** @return array<string, mixed> */
    private function meta(): array
    {
        return [
            'statuses' => ReservationStatus::options(),
            'sources' => ReservationSource::options(),
            'depositStatuses' => DepositStatus::options(),
            'waitlistStatuses' => WaitlistStatus::options(),
            'defaults' => [
                'duration_minutes' => (int) config('reservations.default_duration_minutes', 120),
                'buffer_minutes' => (int) config('reservations.default_buffer_minutes', 15),
                'max_party_size' => (int) config('reservations.max_party_size', 40),
            ],
        ];
    }
}
