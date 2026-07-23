<?php

namespace App\Modules\Reservations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Services\ReservationTableSync;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\View\View;

/**
 * Müşterinin e-postasındaki onay/iptal bağlantısı: /r/{token}.
 *
 * Kimlik = 40 karakter opak confirmation_token (denetim kaydında maskeli).
 * Oturum yok; yalnız kendi rezervasyonunu görür/iptal eder. Hız sınırlı.
 * Görünüm bu modülün kendi Blade'idir (resources/views/reservations/) —
 * public menü Blade'ine dokunulmaz.
 */
class ReservationLinkController extends Controller
{
    public function show(Request $request, string $token): View
    {
        $reservation = $this->resolve($request, $token);

        return view('reservations.manage', [
            'reservation' => $reservation,
            'canCancel' => ! $reservation->status->isFinal(),
        ]);
    }

    public function cancel(Request $request, string $token): RedirectResponse
    {
        $reservation = $this->resolve($request, $token);

        if (! $reservation->status->isFinal()) {
            $reservation->status = ReservationStatus::Cancelled;
            $reservation->cancelled_at = now();
            $reservation->cancel_reason = 'Müşteri bağlantı üzerinden iptal etti';
            $reservation->save();

            $reservation->load('tables');
            app(ReservationTableSync::class)->release($reservation);
        }

        return redirect('/r/'.$token)->with('status', 'cancelled');
    }

    private function resolve(Request $request, string $token): Reservation
    {
        $limiterKey = 'reservation-link:'.sha1((string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 30)) {
            abort(429);
        }

        RateLimiter::hit($limiterKey, 60);

        if (preg_match('/^[a-f0-9]{40}$/', $token) !== 1) {
            abort(404);
        }

        $reservation = Reservation::withoutTenancy()
            ->where('confirmation_token', $token)
            ->first();

        abort_if($reservation === null, 404);

        return $reservation;
    }
}
