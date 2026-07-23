<?php

namespace App\Modules\Reservations\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reservations\Enums\WaitlistStatus;
use App\Modules\Reservations\Models\WaitlistEntry;
use App\Modules\Reservations\Support\ReservationPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Bekleme listesi (Faz-9). Sıra = açık girdiler, geliş sırasına göre;
 * tahmini süre = personel tahmini (quoted) yoksa sıra × slot dakikası.
 */
class WaitlistController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', WaitlistEntry::class);

        $query = WaitlistEntry::query();

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        // Varsayılan: bugünün listesi (açıklar + bugünkü kapananlar).
        $query->where(function ($q): void {
            $q->whereIn('status', [WaitlistStatus::Waiting->value, WaitlistStatus::Notified->value])
                ->orWhere('created_at', '>=', now()->startOfDay());
        });

        $entries = $query->orderBy('created_at')->get();

        $slot = (int) config('reservations.waitlist_slot_minutes', 15);
        $position = 0;

        $rows = $entries->map(function (WaitlistEntry $entry) use (&$position, $slot): array {
            if ($entry->status->isOpen()) {
                $position++;
            }

            return ReservationPresenter::waitlistView($entry, $position, $slot);
        })->values();

        return response()->json([
            'waitlist' => $rows,
            'open_count' => $entries->filter(fn (WaitlistEntry $e) => $e->status->isOpen())->count(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', WaitlistEntry::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'customer_name' => ['required', 'string', 'max:120'],
            'customer_phone' => ['nullable', 'string', 'max:30'],
            'party_size' => ['required', 'integer', 'min:1', 'max:'.(int) config('reservations.max_party_size', 40)],
            'note' => ['nullable', 'string', 'max:255'],
            'quoted_wait_minutes' => ['nullable', 'integer', 'min:0', 'max:600'],
        ]);

        $owned = \App\Modules\Tenancy\Models\Branch::query()
            ->withoutGlobalScopes()
            ->where('id', (int) $data['branch_id'])
            ->where('tenant_id', (int) $request->user()->tenant_id)
            ->exists();

        if (! $owned) {
            throw ValidationException::withMessages(['branch_id' => ['Geçersiz şube.']]);
        }

        $entry = new WaitlistEntry([
            'customer_name' => $data['customer_name'],
            'customer_phone' => $data['customer_phone'] ?? null,
            'party_size' => (int) $data['party_size'],
            'note' => $data['note'] ?? null,
            'quoted_wait_minutes' => $data['quoted_wait_minutes'] ?? null,
            'status' => WaitlistStatus::Waiting->value,
            'source' => 'panel',
        ]);
        $entry->branch_id = (int) $data['branch_id'];
        $entry->save();

        return response()->json([
            'entry' => ReservationPresenter::waitlistView(
                $entry,
                $this->openPosition($entry),
                (int) config('reservations.waitlist_slot_minutes', 15),
            ),
        ], 201);
    }

    public function update(Request $request, WaitlistEntry $entry): JsonResponse
    {
        $this->authorize('update', $entry);

        $data = $request->validate([
            'customer_name' => ['sometimes', 'string', 'max:120'],
            'customer_phone' => ['nullable', 'string', 'max:30'],
            'party_size' => ['sometimes', 'integer', 'min:1', 'max:'.(int) config('reservations.max_party_size', 40)],
            'note' => ['nullable', 'string', 'max:255'],
            'quoted_wait_minutes' => ['nullable', 'integer', 'min:0', 'max:600'],
        ]);

        $entry->fill($data)->save();

        return response()->json([
            'entry' => ReservationPresenter::waitlistView(
                $entry,
                $this->openPosition($entry),
                (int) config('reservations.waitlist_slot_minutes', 15),
            ),
        ]);
    }

    /** Durum: çağır (müşteri geldi bildirimi) / masaya al / iptal / gelmedi. */
    public function setStatus(Request $request, WaitlistEntry $entry): JsonResponse
    {
        $this->authorize('update', $entry);

        $data = $request->validate([
            'status' => ['required', Rule::enum(WaitlistStatus::class)],
        ]);

        $target = WaitlistStatus::from($data['status']);

        $allowed = match ($entry->status) {
            WaitlistStatus::Waiting => [WaitlistStatus::Notified, WaitlistStatus::Seated, WaitlistStatus::Cancelled],
            WaitlistStatus::Notified => [WaitlistStatus::Seated, WaitlistStatus::Cancelled, WaitlistStatus::Expired],
            default => [],
        };

        if (! in_array($target, $allowed, true)) {
            throw ValidationException::withMessages([
                'status' => [sprintf("'%s' durumundan '%s' durumuna geçilemez.", $entry->status->label(), $target->label())],
            ]);
        }

        $entry->status = $target;

        match ($target) {
            WaitlistStatus::Notified => $entry->notified_at = now(),
            WaitlistStatus::Seated => $entry->seated_at = now(),
            default => null,
        };

        $entry->save();

        return response()->json([
            'entry' => ReservationPresenter::waitlistView(
                $entry,
                $this->openPosition($entry),
                (int) config('reservations.waitlist_slot_minutes', 15),
            ),
        ]);
    }

    /** Girdinin açıklar arasındaki sırası (1 tabanlı; kapalıysa son sıra). */
    private function openPosition(WaitlistEntry $entry): int
    {
        if (! $entry->status->isOpen()) {
            return 0;
        }

        return WaitlistEntry::query()
            ->open()
            ->where('branch_id', $entry->branch_id)
            ->where('created_at', '<=', $entry->created_at)
            ->where('id', '<=', $entry->id)
            ->count();
    }
}
