<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Services\NotifyEmitter;
use App\Modules\Portal\Services\PortalShiftService;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Models\TimeEntryBreak;
use App\Modules\Shifts\Services\TimeClockService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Portal "Mesaim": kişinin KENDİ mesai/mola uçları — PIN'SİZ.
 *
 * Device-clock (§13) ortak tablette PIN ister çünkü kim olduğu belirsizdir.
 * Portalda ise oturum SAHİBİ eylemi yapar → kimlik zaten oturumdan gelir,
 * ayrıca PIN sorulmaz. Mola/tuvalet başlat-bitir §8 NotifyEmitter ile
 * yöneticiye + o an mesaide olan diğer personele bildirilir (şube-izole).
 */
class PortalClockController extends Controller
{
    public function __construct(
        private readonly TimeClockService $clock,
        private readonly PortalShiftService $shifts,
        private readonly NotifyEmitter $notify,
    ) {
    }

    /** Anlık durum (Mesaim ekranı ilk yükleme + poll). */
    public function state(Request $request): JsonResponse
    {
        return response()->json($this->shifts->state($request->user()));
    }

    /** Mesai başlat (clock in). */
    public function clockIn(Request $request): JsonResponse
    {
        $this->clock->clockIn($request->user(), [
            'method' => 'portal',
            'ip' => $request->ip(),
        ]);

        return $this->stateResponse($request);
    }

    /** Mesai bitir (clock out). */
    public function clockOut(Request $request): JsonResponse
    {
        $this->clock->clockOut($request->user(), [
            'method' => 'portal',
            'ip' => $request->ip(),
        ]);

        return $this->stateResponse($request);
    }

    /** Mola başlat (normal veya tuvalet). */
    public function breakStart(Request $request): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['nullable', 'in:break,toilet'],
        ]);

        $kind = ($data['kind'] ?? TimeEntryBreak::KIND_BREAK) === TimeEntryBreak::KIND_TOILET
            ? TimeEntryBreak::KIND_TOILET
            : TimeEntryBreak::KIND_BREAK;

        $break = $this->clock->breakStart($request->user(), $kind);

        // §8: yönetici + o an mesaide olan diğer personel bilgilendirilir.
        $this->notify->staffBreak($request->user(), $break, 'start');

        return $this->stateResponse($request);
    }

    /** Mola bitir. */
    public function breakEnd(Request $request): JsonResponse
    {
        $break = $this->clock->breakEnd($request->user());

        $this->notify->staffBreak($request->user(), $break, 'end');

        return $this->stateResponse($request);
    }

    /**
     * Mesai geçmişi: kişinin son 14 mesai kaydı (en yeni önce).
     * Süre hesabı state()/reports() ile UYUMLU: canlı çalışılan dakika ve
     * tamamlanmış mola/tuvalet dakikaları (TimeEntryBreak::minutes()).
     */
    public function history(Request $request): JsonResponse
    {
        $now = Carbon::now();

        $entries = TimeEntry::query()
            ->where('user_id', $request->user()->id)
            ->with('breaks')
            ->orderByDesc('clock_in_at')
            ->limit(14)
            ->get()
            ->map(fn (TimeEntry $entry) => [
                'id' => (int) $entry->id,
                'date' => $entry->clock_in_at->toDateString(),
                'clock_in_at' => $entry->clock_in_at->toIso8601String(),
                'clock_out_at' => $entry->clock_out_at?->toIso8601String(),
                'worked_min' => $this->workedMinutes($entry, $now),
                'break_min' => $this->breakMinutes($entry, TimeEntryBreak::KIND_BREAK),
                'toilet_min' => $this->breakMinutes($entry, TimeEntryBreak::KIND_TOILET),
                'status' => $entry->status,
            ])
            ->values();

        return response()->json(['entries' => $entries]);
    }

    private function stateResponse(Request $request): JsonResponse
    {
        return response()->json($this->shifts->state($request->user()));
    }

    /**
     * Canlı çalışılan dakika (PortalShiftService ile aynı mantık): kapalı
     * kayıtta finalize edilmiş worked_min; açık kayıtta (şimdi − giriş) −
     * tamamlanmış molalar.
     */
    private function workedMinutes(TimeEntry $entry, Carbon $now): int
    {
        if (! $entry->isOpen() && $entry->worked_min !== null) {
            return (int) $entry->worked_min;
        }

        $end = $entry->clock_out_at ?? $now;
        $gross = max(0, (int) $entry->clock_in_at->diffInMinutes($end));

        return max(0, $gross - $this->breakMinutes($entry, null));
    }

    /** Tamamlanmış molaların (opsiyonel tür süzgeciyle) toplam dakikası. */
    private function breakMinutes(TimeEntry $entry, ?string $kind): int
    {
        return (int) $entry->breaks
            ->when($kind !== null, fn ($c) => $c->where('kind', $kind))
            ->filter(fn (TimeEntryBreak $b) => $b->ended_at !== null)
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());
    }
}
