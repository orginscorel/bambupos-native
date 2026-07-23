<?php

namespace App\Modules\Reservations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reservations\Enums\DepositStatus;
use App\Modules\Reservations\Enums\ReservationSource;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Reservations\Models\Reservation;
use App\Modules\Reservations\Services\AvailabilityService;
use App\Modules\Reservations\Services\ReservationMailer;
use App\Modules\Reservations\Services\ReservationService;
use App\Modules\Reservations\Support\ReservationPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Panel rezervasyon API'si. Tüm sorgular tenant-scope'lu (ADR-004);
 * yabancı kayıt model binding'de 404 üretir. Hassas alan sunumu
 * ReservationPresenter'da izne bağlanır.
 */
class ReservationController extends Controller
{
    public function __construct(
        private readonly ReservationService $service,
        private readonly AvailabilityService $availability,
        private readonly ReservationMailer $mailer,
    ) {
    }

    /** Liste: gün/hafta aralığı + filtreler (takvim ekranı da bunu kullanır). */
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Reservation::class);

        $query = Reservation::query()->with(['tables:id,name,number,capacity', 'area:id,name', 'creator:id,name']);

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        if ($request->filled('from')) {
            $query->where('reserved_at', '>=', Carbon::parse((string) $request->query('from'))->startOfDay());
        }

        if ($request->filled('to')) {
            $query->where('reserved_at', '<=', Carbon::parse((string) $request->query('to'))->endOfDay());
        }

        if ($request->filled('status')) {
            $query->where('status', (string) $request->query('status'));
        }

        if ($request->boolean('open_only')) {
            $query->blocking();
        }

        if ($request->filled('q')) {
            $q = (string) $request->query('q');
            $query->where(function ($sub) use ($q): void {
                $sub->where('customer_name', 'like', "%{$q}%")
                    ->orWhere('customer_phone', 'like', "%{$q}%")
                    ->orWhere('customer_email', 'like', "%{$q}%");
            });
        }

        $reservations = $query->orderBy('reserved_at')
            ->paginate(min((int) $request->query('per_page', 100), 300));

        $viewer = $request->user();
        $reservations->getCollection()->transform(
            fn (Reservation $r): array => ReservationPresenter::panelView($r, $viewer)
        );

        return response()->json(['reservations' => $reservations]);
    }

    /** Masa uygunluk haritası (form: tarih/saat/süre girilince çağrılır). */
    public function availability(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Reservation::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'reserved_at' => ['required', 'date'],
            'duration_minutes' => ['sometimes', 'integer', 'min:15', 'max:1440'],
            'buffer_minutes' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'ignore_reservation_id' => ['sometimes', 'integer'],
        ]);

        $tables = $this->availability->tableAvailability(
            (int) $data['branch_id'],
            Carbon::parse($data['reserved_at']),
            (int) ($data['duration_minutes'] ?? config('reservations.default_duration_minutes', 120)),
            (int) ($data['buffer_minutes'] ?? config('reservations.default_buffer_minutes', 15)),
            isset($data['ignore_reservation_id']) ? (int) $data['ignore_reservation_id'] : null,
        );

        return response()->json(['tables' => $tables]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Reservation::class);

        $data = $this->validatePayload($request, creating: true);
        $this->assertBranchBelongsToTenant($request, (int) $data['branch_id']);

        $reservation = $this->service->create(
            $data,
            array_map('intval', $data['table_ids'] ?? []),
            $request->user(),
            ReservationSource::Panel->value,
        );

        return response()->json([
            'reservation' => ReservationPresenter::panelView($reservation->load(['tables', 'area', 'creator']), $request->user()),
        ], 201);
    }

    public function show(Request $request, Reservation $reservation): JsonResponse
    {
        $this->authorize('view', $reservation);

        return response()->json([
            'reservation' => ReservationPresenter::panelView(
                $reservation->load(['tables', 'area', 'creator']),
                $request->user(),
            ),
        ]);
    }

    public function update(Request $request, Reservation $reservation): JsonResponse
    {
        $this->authorize('update', $reservation);

        $data = $this->validatePayload($request, creating: false);

        $reservation = $this->service->update(
            $reservation,
            $data,
            array_key_exists('table_ids', $data) ? array_map('intval', $data['table_ids'] ?? []) : null,
        );

        return response()->json([
            'reservation' => ReservationPresenter::panelView($reservation->load(['tables', 'area', 'creator']), $request->user()),
        ]);
    }

    public function destroy(Reservation $reservation): JsonResponse
    {
        $this->authorize('delete', $reservation);

        // Açık rezervasyon silinirken masası serbest bırakılır.
        $reservation->load('tables');
        app(\App\Modules\Reservations\Services\ReservationTableSync::class)->release($reservation);
        $reservation->delete();

        return response()->json(null, 204);
    }

    /** Durum makinesi geçişi (onay/geldi/masaya alındı/iptal/no-show...). */
    public function setStatus(Request $request, Reservation $reservation): JsonResponse
    {
        $this->authorize('manage', $reservation);

        $data = $request->validate([
            'status' => ['required', Rule::enum(ReservationStatus::class)],
            'reason' => ['nullable', 'string', 'max:255'],
        ]);

        $reservation = $this->service->transition(
            $reservation,
            ReservationStatus::from($data['status']),
            $data['reason'] ?? null,
        );

        return response()->json([
            'reservation' => ReservationPresenter::panelView($reservation->load(['tables', 'area', 'creator']), $request->user()),
        ]);
    }

    /** Kapora durumu güncelleme (alındı/iade/yandı). */
    public function setDeposit(Request $request, Reservation $reservation): JsonResponse
    {
        $this->authorize('manage', $reservation);

        $data = $request->validate([
            'deposit_minor' => ['sometimes', 'integer', 'min:0', 'max:100000000'],
            'deposit_status' => ['required', Rule::enum(DepositStatus::class)],
        ]);

        if (array_key_exists('deposit_minor', $data)) {
            $reservation->deposit_minor = (int) $data['deposit_minor'];
        }
        $reservation->deposit_status = DepositStatus::from($data['deposit_status']);
        $reservation->save();

        return response()->json([
            'reservation' => ReservationPresenter::panelView($reservation->load(['tables', 'area', 'creator']), $request->user()),
        ]);
    }

    /** Elle hatırlatma gönder (e-posta; SMTP paneli üzerinden). */
    public function remind(Request $request, Reservation $reservation): JsonResponse
    {
        $this->authorize('manage', $reservation);

        $sent = $this->mailer->sendReminder($reservation);

        $reservation->reminder_status = $sent ? 'sent' : ($reservation->customer_email ? 'failed' : 'skipped');
        $reservation->reminder_sent_at = $sent ? now() : $reservation->reminder_sent_at;
        $reservation->save();

        return response()->json([
            'sent' => $sent,
            'message' => $sent
                ? 'Hatırlatma e-postası gönderildi.'
                : 'Gönderilemedi: müşterinin e-posta adresi yok ya da SMTP hatası (log).',
        ], $sent ? 200 : 422);
    }

    /** No-show raporu: aralık bazlı özet + tekrar eden müşteriler. */
    public function noShowReport(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Reservation::class);

        $from = $request->filled('from')
            ? Carbon::parse((string) $request->query('from'))->startOfDay()
            : now()->subDays(30)->startOfDay();
        $to = $request->filled('to')
            ? Carbon::parse((string) $request->query('to'))->endOfDay()
            : now()->endOfDay();

        $base = Reservation::query()
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', (int) $request->query('branch_id')))
            ->whereBetween('reserved_at', [$from, $to]);

        $total = (clone $base)->count();
        $noShows = (clone $base)->where('status', ReservationStatus::NoShow->value)->count();
        $completed = (clone $base)->where('status', ReservationStatus::Completed->value)->count();
        $cancelled = (clone $base)->where('status', ReservationStatus::Cancelled->value)->count();
        $forfeitedDeposits = (clone $base)
            ->where('deposit_status', DepositStatus::Forfeited->value)
            ->sum('deposit_minor');

        // Tekrar eden no-show müşterileri (telefon anahtar; boşlar hariç)
        $repeat = (clone $base)
            ->where('status', ReservationStatus::NoShow->value)
            ->whereNotNull('customer_phone')
            ->selectRaw('customer_phone, MAX(customer_name) as customer_name, COUNT(*) as no_show_count')
            ->groupBy('customer_phone')
            ->orderByDesc('no_show_count')
            ->limit(20)
            ->get();

        $viewer = $request->user();

        $rows = (clone $base)
            ->where('status', ReservationStatus::NoShow->value)
            ->with(['tables:id,name,number,capacity'])
            ->orderByDesc('reserved_at')
            ->limit(200)
            ->get()
            ->map(fn (Reservation $r): array => ReservationPresenter::panelView($r, $viewer));

        return response()->json([
            'report' => [
                'from' => $from->toDateString(),
                'to' => $to->toDateString(),
                'total' => $total,
                'no_shows' => $noShows,
                'completed' => $completed,
                'cancelled' => $cancelled,
                'no_show_rate' => $total > 0 ? round($noShows * 100 / $total, 1) : 0.0,
                'forfeited_deposit_minor' => (int) $forfeitedDeposits,
                'repeat_offenders' => $repeat,
                'rows' => $rows,
            ],
        ]);
    }

    /** Yabancı kiracının şubesine yazma denemesi 422 (Orders sözleşmesiyle aynı). */
    private function assertBranchBelongsToTenant(Request $request, int $branchId): void
    {
        $owned = \App\Modules\Tenancy\Models\Branch::query()
            ->withoutGlobalScopes()
            ->where('id', $branchId)
            ->where('tenant_id', (int) $request->user()->tenant_id)
            ->exists();

        if (! $owned) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'branch_id' => ['Geçersiz şube.'],
            ]);
        }
    }

    /** @return array<string, mixed> */
    private function validatePayload(Request $request, bool $creating): array
    {
        $rules = [
            'branch_id' => [$creating ? 'required' : 'sometimes', 'integer'],
            'customer_name' => [$creating ? 'required' : 'sometimes', 'string', 'max:120'],
            'customer_phone' => ['nullable', 'string', 'max:30'],
            'customer_email' => ['nullable', 'email', 'max:190'],
            'reserved_at' => [$creating ? 'required' : 'sometimes', 'date'],
            'duration_minutes' => ['sometimes', 'integer', 'min:15', 'max:1440'],
            'buffer_minutes' => ['sometimes', 'integer', 'min:0', 'max:240'],
            'party_size' => [$creating ? 'required' : 'sometimes', 'integer', 'min:1', 'max:'.(int) config('reservations.max_party_size', 40)],
            'area_id' => ['nullable', 'integer'],
            'table_ids' => ['sometimes', 'array', 'max:10'],
            'table_ids.*' => ['integer'],
            'special_note' => ['nullable', 'string', 'max:500'],
            'allergy_note' => ['nullable', 'string', 'max:1000'],
            'occasion' => ['nullable', 'string', 'max:30'],
            'occasion_note' => ['nullable', 'string', 'max:255'],
            'deposit_minor' => ['sometimes', 'integer', 'min:0', 'max:100000000'],
            'deposit_status' => ['sometimes', Rule::enum(DepositStatus::class)],
        ];

        if ($creating) {
            // Panelden açılan kayıt talep/onay-bekliyor/onaylı başlayabilir.
            $rules['status'] = ['sometimes', Rule::in([
                ReservationStatus::Requested->value,
                ReservationStatus::PendingConfirmation->value,
                ReservationStatus::Confirmed->value,
            ])];
        }

        return $request->validate($rules);
    }
}
