<?php

namespace App\Modules\Shifts\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\LeaveRequest;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\TimeEntry;
use Carbon\CarbonImmutable;

/**
 * Devam takibi özeti: çalışılan süre, fazla mesai, eksik çalışma,
 * geç kalma, erken çıkış, izin/rapor/tatil ve devamsızlık.
 *
 * Devamsızlık iki kaynaktan gelir:
 *  - kayıt: yöneticinin açtığı 'absence' türü onaylı kayıtlar,
 *  - tespit: geçmişte planlı vardiyası olup mesai kaydı ve onaylı izni
 *    olmayan günler (auto_absent).
 */
class AttendanceService
{
    /**
     * @return array<int, array<string, mixed>> personel başına özet
     */
    public function summary(CarbonImmutable $from, CarbonImmutable $to, ?int $onlyUserId = null): array
    {
        $users = User::ofCurrentTenant()
            ->where('is_active', true)
            ->when($onlyUserId !== null, fn ($q) => $q->where('id', $onlyUserId))
            ->orderBy('name')
            ->get(['id', 'name', 'position', 'branch_id']);

        $entries = TimeEntry::query()
            ->where('clock_in_at', '>=', $from)
            ->where('clock_in_at', '<', $to)
            ->where('status', TimeEntry::STATUS_CLOSED)
            ->get()
            ->groupBy('user_id');

        $shifts = Shift::query()
            ->where('starts_at', '>=', $from)
            ->where('starts_at', '<', $to)
            ->get()
            ->groupBy('user_id');

        $leaves = LeaveRequest::query()
            ->where('status', LeaveRequest::STATUS_APPROVED)
            ->whereDate('starts_on', '<=', $to->toDateString())
            ->whereDate('ends_on', '>=', $from->toDateString())
            ->get()
            ->groupBy('user_id');

        return $users->map(function (User $user) use ($entries, $shifts, $leaves, $from, $to): array {
            /** @var \Illuminate\Support\Collection<int, TimeEntry> $userEntries */
            $userEntries = $entries->get($user->id, collect());
            /** @var \Illuminate\Support\Collection<int, Shift> $userShifts */
            $userShifts = $shifts->get($user->id, collect());
            /** @var \Illuminate\Support\Collection<int, LeaveRequest> $userLeaves */
            $userLeaves = $leaves->get($user->id, collect());

            $leaveDays = [];
            foreach (LeaveRequest::TYPES as $type) {
                $leaveDays[$type] = (int) $userLeaves
                    ->where('type', $type)
                    ->sum(fn (LeaveRequest $l) => $this->daysWithin($l, $from, $to));
            }

            // Tespit edilen devamsızlık: geçmiş planlı gün − mesai − onaylı izin.
            $autoAbsent = $userShifts
                ->filter(fn (Shift $s) => $s->ends_at->isPast())
                ->filter(function (Shift $s) use ($userEntries, $userLeaves): bool {
                    $day = $s->starts_at->toDateString();

                    $hasEntry = $userEntries->contains(
                        fn (TimeEntry $e) => $e->shift_id === $s->id || $e->clock_in_at->toDateString() === $day
                    );

                    $hasLeave = $userLeaves->contains(
                        fn (LeaveRequest $l) => $l->starts_on->toDateString() <= $day && $l->ends_on->toDateString() >= $day
                    );

                    return ! $hasEntry && ! $hasLeave;
                })
                ->unique(fn (Shift $s) => $s->starts_at->toDateString())
                ->count();

            return [
                'user' => ['id' => $user->id, 'name' => $user->name, 'position' => $user->position],
                'days_worked' => $userEntries->unique(fn (TimeEntry $e) => $e->clock_in_at->toDateString())->count(),
                'worked_min' => (int) $userEntries->sum('worked_min'),
                'break_min' => (int) $userEntries->sum('break_total_min'),
                'overtime_min' => (int) $userEntries->sum('overtime_min'),
                'missing_min' => (int) $userEntries->sum('missing_min'),
                'late_count' => $userEntries->where('late_min', '>', 0)->count(),
                'late_min' => (int) $userEntries->sum('late_min'),
                'early_leave_count' => $userEntries->where('early_leave_min', '>', 0)->count(),
                'planned_shifts' => $userShifts->count(),
                'leave_days' => $leaveDays,
                'auto_absent_days' => $autoAbsent,
            ];
        })->all();
    }

    /** İznin rapor aralığına düşen gün sayısı. */
    private function daysWithin(LeaveRequest $leave, CarbonImmutable $from, CarbonImmutable $to): int
    {
        $start = max($leave->starts_on->startOfDay()->getTimestamp(), $from->startOfDay()->getTimestamp());
        $end = min($leave->ends_on->startOfDay()->getTimestamp(), $to->subDay()->startOfDay()->getTimestamp());

        if ($end < $start) {
            return 0;
        }

        return (int) (($end - $start) / 86400) + 1;
    }
}
