<?php

namespace App\Modules\Portal\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Models\TimeEntryBreak;
use App\Modules\Shifts\Services\TimeClockService;
use Illuminate\Support\Carbon;

/**
 * Portal "Mesaim" + "Raporlarım" sunumu.
 *
 * Kişinin KENDİ mesai/mola durumunu (canlı süreler dahil) ve temel
 * raporlarını (bugün/bu ay çalışılan saat + mola/tuvalet dakikası + geçmiş)
 * time_entries / time_entry_breaks üzerinden türetir. Yeni tablo yok.
 */
class PortalShiftService
{
    public function __construct(private readonly TimeClockService $clock)
    {
    }

    /**
     * Kişinin anlık mesai/mola durumu (Mesaim ekranı için).
     *
     * @return array<string, mixed>
     */
    public function state(User $user): array
    {
        $entry = $this->clock->openEntryFor($user);
        $now = Carbon::now();

        $openBreak = $entry?->openBreak();
        $todayShift = $this->todayShift($user);

        return [
            'status' => $entry === null ? 'off' : 'working',
            'on_break' => $openBreak !== null,
            'break_kind' => $openBreak?->kind,
            'break_started_at' => $openBreak?->started_at?->toIso8601String(),
            'entry' => $entry === null ? null : [
                'id' => (int) $entry->id,
                'clock_in_at' => $entry->clock_in_at->toIso8601String(),
                'worked_min' => $this->liveWorkedMinutes($entry, $now),
                'break_total_min' => $this->breakMinutes($entry, null),
                'toilet_total_min' => $this->breakMinutes($entry, TimeEntryBreak::KIND_TOILET),
                'breaks' => $entry->breaks->map(fn (TimeEntryBreak $b) => [
                    'kind' => $b->kind,
                    'kind_label' => $b->kindLabel(),
                    'started_at' => $b->started_at->toIso8601String(),
                    'ended_at' => $b->ended_at?->toIso8601String(),
                ])->values(),
            ],
            'today_shift' => $todayShift === null ? null : [
                'starts_at' => $todayShift->starts_at->toIso8601String(),
                'ends_at' => $todayShift->ends_at->toIso8601String(),
                'position' => $todayShift->position ?? null,
            ],
            'server_now' => $now->toIso8601String(),
        ];
    }

    /**
     * Temel raporlar: bugün + bu ay çalışılan dakika, mola/tuvalet dakikası,
     * ve son mesai kayıtları (geçmiş).
     *
     * @return array<string, mixed>
     */
    public function reports(User $user): array
    {
        $now = Carbon::now();
        $todayStart = $now->copy()->startOfDay();
        $monthStart = $now->copy()->startOfMonth();

        $entries = TimeEntry::query()
            ->where('user_id', $user->id)
            ->where('clock_in_at', '>=', $monthStart)
            ->orderByDesc('clock_in_at')
            ->with('breaks')
            ->get();

        $today = ['worked_min' => 0, 'break_min' => 0, 'toilet_min' => 0, 'entries' => 0];
        $month = ['worked_min' => 0, 'break_min' => 0, 'toilet_min' => 0, 'entries' => 0];

        foreach ($entries as $entry) {
            $worked = $this->liveWorkedMinutes($entry, $now);
            $breakMin = $this->breakMinutes($entry, TimeEntryBreak::KIND_BREAK);
            $toiletMin = $this->breakMinutes($entry, TimeEntryBreak::KIND_TOILET);

            $month['worked_min'] += $worked;
            $month['break_min'] += $breakMin;
            $month['toilet_min'] += $toiletMin;
            $month['entries']++;

            if ($entry->clock_in_at->gte($todayStart)) {
                $today['worked_min'] += $worked;
                $today['break_min'] += $breakMin;
                $today['toilet_min'] += $toiletMin;
                $today['entries']++;
            }
        }

        $history = $entries->take(30)->map(fn (TimeEntry $e) => [
            'id' => (int) $e->id,
            'date' => $e->clock_in_at->toDateString(),
            'clock_in_at' => $e->clock_in_at->toIso8601String(),
            'clock_out_at' => $e->clock_out_at?->toIso8601String(),
            'status' => $e->status,
            'worked_min' => $this->liveWorkedMinutes($e, $now),
            'break_min' => $this->breakMinutes($e, TimeEntryBreak::KIND_BREAK),
            'toilet_min' => $this->breakMinutes($e, TimeEntryBreak::KIND_TOILET),
        ])->values();

        return ['today' => $today, 'month' => $month, 'history' => $history];
    }

    /** Molaların (opsiyonel tür süzgeciyle) tamamlanmış toplam dakikası. */
    private function breakMinutes(TimeEntry $entry, ?string $kind): int
    {
        return (int) $entry->breaks
            ->when($kind !== null, fn ($c) => $c->where('kind', $kind))
            ->filter(fn (TimeEntryBreak $b) => $b->ended_at !== null)
            ->sum(fn (TimeEntryBreak $b) => $b->minutes());
    }

    /**
     * Canlı çalışılan dakika: kapalı kayıtta finalize edilmiş worked_min,
     * açık kayıtta (şimdi - giriş) - tamamlanmış molalar.
     */
    private function liveWorkedMinutes(TimeEntry $entry, Carbon $now): int
    {
        if (! $entry->isOpen() && $entry->worked_min !== null) {
            return (int) $entry->worked_min;
        }

        $end = $entry->clock_out_at ?? $now;
        $gross = max(0, (int) $entry->clock_in_at->diffInMinutes($end));
        $breakMin = $this->breakMinutes($entry, null);

        return max(0, $gross - $breakMin);
    }

    /** Bugüne denk gelen (±4 saat pencere) kişisel vardiya. */
    private function todayShift(User $user): ?Shift
    {
        $now = Carbon::now();

        return Shift::query()
            ->where('user_id', $user->id)
            ->where('starts_at', '<=', $now->copy()->addHours(4))
            ->where('ends_at', '>=', $now->copy()->subHours(4))
            ->get()
            ->sortBy(fn (Shift $s) => abs((int) $s->starts_at->diffInMinutes($now, false)))
            ->first();
    }
}
