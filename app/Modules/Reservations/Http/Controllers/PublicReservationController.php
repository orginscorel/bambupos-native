<?php

namespace App\Modules\Reservations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reservations\Enums\ReservationSource;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Services\ReservationService;
use App\Modules\Reservations\Support\ReservationPresenter;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Venue\Services\QrTokenResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\RateLimiter;

/**
 * PUBLIC (oturumsuz) rezervasyon talebi — QR menü buraya bağlanır.
 *
 * POST /api/v1/public/reservations
 *   Kimlik: YALNIZ QR token (ADR-008; masa VEYA şube token'ı kabul edilir —
 *   rezervasyon şube kapsamındadır). İstekten tenant/branch/table id'si asla
 *   alınmaz. Kayıt her zaman "Talep alındı" durumunda açılır; personel
 *   panelden onaylar (masa ataması da panelde yapılır). Hız sınırı:
 *   token+IP başına dakikalık (NAT gerçeği — PublicOrderController deseni).
 */
class PublicReservationController extends Controller
{
    public function __construct(
        private readonly QrTokenResolver $resolver,
        private readonly ReservationService $service,
        private readonly TenantContext $context,
    ) {
    }

    public function store(Request $request): JsonResponse
    {
        $maxDays = (int) config('reservations.public_max_days_ahead', 60);

        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'customer_name' => ['required', 'string', 'max:120'],
            'customer_phone' => ['required', 'string', 'max:30'],
            'customer_email' => ['nullable', 'email', 'max:190'],
            'date' => ['required', 'date_format:Y-m-d', 'after_or_equal:today', 'before_or_equal:'.now()->addDays($maxDays)->toDateString()],
            'time' => ['required', 'date_format:H:i'],
            'party_size' => ['required', 'integer', 'min:1', 'max:'.(int) config('reservations.max_party_size', 40)],
            'note' => ['nullable', 'string', 'max:500'],
            'allergy_note' => ['nullable', 'string', 'max:1000'],
            'occasion' => ['nullable', 'string', 'max:30'],
        ]);

        // Hız sınırı: token+IP ikilisi (NAT arkasında IP tek başına yetmez).
        $limiterKey = 'public-reservation:'.sha1($data['token'].'|'.(string) $request->ip());
        $perMinute = (int) config('reservations.public_rate_per_minute', 5);

        if (RateLimiter::tooManyAttempts($limiterKey, $perMinute)) {
            return response()->json([
                'message' => 'Çok sık istek gönderildi. Lütfen biraz bekleyin.',
            ], 429)->header('Retry-After', (string) RateLimiter::availableIn($limiterKey));
        }

        RateLimiter::hit($limiterKey, 60);

        $resolution = $this->resolver->resolve($data['token'], $request);

        if ($resolution->status === 'revoked' || $resolution->status === 'inactive') {
            return response()->json(['message' => 'Bu QR kod artık geçerli değil. Lütfen personelden yeni kodu isteyin.'], 410);
        }

        if ($resolution->status !== 'ok' || $resolution->branch === null) {
            return response()->json(['message' => 'Geçersiz QR kod.'], 404);
        }

        // Müşteri şube duvar saatiyle seçer; UTC anına çevrilir.
        $reservedAt = ReservationService::parseBranchTime(
            (int) $resolution->branch->id,
            $data['date'].' '.$data['time'],
        );

        if ($reservedAt->lte(now())) {
            return response()->json(['message' => 'Geçmiş bir saat için rezervasyon yapılamaz.'], 422);
        }

        // Yazma bağlamı: token'dan çözülen kiracı (ADR-008/ADR-004).
        $this->context->setTenant((int) $resolution->branch->tenant_id);

        try {
            $reservation = $this->service->create(
                [
                    'branch_id' => (int) $resolution->branch->id,
                    'customer_name' => $data['customer_name'],
                    'customer_phone' => $data['customer_phone'],
                    'customer_email' => $data['customer_email'] ?? null,
                    'reserved_at' => $reservedAt,
                    'party_size' => (int) $data['party_size'],
                    'special_note' => $data['note'] ?? null,
                    'allergy_note' => $data['allergy_note'] ?? null,
                    'occasion' => $data['occasion'] ?? null,
                    'status' => ReservationStatus::Requested->value,
                ],
                tableIds: [],   // masa atamasını personel onayda yapar
                actor: null,
                source: ReservationSource::Qr->value,
            );
        } finally {
            $this->context->forget();
        }

        return response()->json([
            'reservation' => ReservationPresenter::publicView($reservation),
            'message' => 'Rezervasyon talebiniz alındı. Onaylandığında bilgilendirileceksiniz.',
        ], 201);
    }
}
