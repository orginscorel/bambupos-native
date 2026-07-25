<?php

namespace App\Modules\Shifts\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\LeaveRequest;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\ShiftSwapRequest;
use App\Modules\Shifts\Models\StaffingRule;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Vardiya planlama çekirdeği: oluşturma (tekrarlı dahil), taşıma,
 * çakışma tespiti, minimum personel uyarıları, değişim talebi onayı.
 */
class ShiftPlanner
{
    /**
     * Vardiya oluşturur. repeat_weeks > 0 ise aynı vardiyayı haftalık
     * kopyalar (repeat_group ile bağlı). Çakışan tekrar günleri atlanır
     * ve 'skipped' listesinde raporlanır.
     *
     * @param  array{branch_id: int, user_id: int, position?: ?string, starts_at: string, ends_at: string, break_min?: int, note?: ?string, repeat_weeks?: int, allow_overlap?: bool}  $data
     * @return array{shifts: array<int, Shift>, skipped: array<int, string>}
     */
    public function create(array $data): array
    {
        $start = CarbonImmutable::parse($data['starts_at']);
        $end = CarbonImmutable::parse($data['ends_at']);

        $this->assertValidWindow($start, $end);

        $repeatWeeks = min(26, max(0, (int) ($data['repeat_weeks'] ?? 0)));
        $allowOverlap = (bool) ($data['allow_overlap'] ?? false);
        $repeatGroup = $repeatWeeks > 0 ? (string) Str::uuid() : null;

        // İlk vardiyada çakışma engeldir (allow_overlap ile bilinçli aşılır).
        $conflicts = $this->conflictsFor((int) $data['user_id'], $start, $end);

        if ($conflicts !== [] && ! $allowOverlap) {
            throw ValidationException::withMessages([
                'starts_at' => ['Bu personelin aynı aralıkta başka vardiyası var.'],
            ])->status(422);
        }

        $created = [];
        $skipped = [];

        for ($week = 0; $week <= $repeatWeeks; $week++) {
            $s = $start->addWeeks($week);
            $e = $end->addWeeks($week);

            if ($week > 0 && ! $allowOverlap && $this->conflictsFor((int) $data['user_id'], $s, $e) !== []) {
                $skipped[] = $s->format('Y-m-d');

                continue;
            }

            $shift = new Shift([
                'branch_id' => (int) $data['branch_id'],
                'user_id' => (int) $data['user_id'],
                'position' => $data['position'] ?? null,
                'starts_at' => $s,
                'ends_at' => $e,
                'break_min' => (int) ($data['break_min'] ?? 0),
                'note' => $data['note'] ?? null,
                'repeat_group' => $repeatGroup,
            ]);
            $shift->created_by_id = Auth::id();
            $shift->save();

            $created[] = $shift;
        }

        return ['shifts' => $created, 'skipped' => $skipped];
    }

    /**
     * Vardiyayı günceller/taşır (sürükle-bırak dahil).
     *
     * @param  array{branch_id?: int, user_id?: int, position?: ?string, starts_at?: string, ends_at?: string, break_min?: int, note?: ?string, allow_overlap?: bool}  $data
     */
    public function update(Shift $shift, array $data): Shift
    {
        $start = isset($data['starts_at']) ? CarbonImmutable::parse($data['starts_at']) : CarbonImmutable::make($shift->starts_at);
        $end = isset($data['ends_at']) ? CarbonImmutable::parse($data['ends_at']) : CarbonImmutable::make($shift->ends_at);
        $userId = (int) ($data['user_id'] ?? $shift->user_id);

        $this->assertValidWindow($start, $end);

        $conflicts = $this->conflictsFor($userId, $start, $end, excludeId: (int) $shift->id);

        if ($conflicts !== [] && ! ($data['allow_overlap'] ?? false)) {
            throw ValidationException::withMessages([
                'starts_at' => ['Bu personelin aynı aralıkta başka vardiyası var.'],
            ])->status(422);
        }

        $shift->fill([
            'branch_id' => $data['branch_id'] ?? $shift->branch_id,
            'user_id' => $userId,
            'position' => array_key_exists('position', $data) ? $data['position'] : $shift->position,
            'starts_at' => $start,
            'ends_at' => $end,
            'break_min' => $data['break_min'] ?? $shift->break_min,
            'note' => array_key_exists('note', $data) ? $data['note'] : $shift->note,
        ])->save();

        return $shift;
    }

    /**
     * Personelin aralıkla çakışan vardiyaları.
     *
     * @return array<int, array{id: int, starts_at: string, ends_at: string}>
     */
    public function conflictsFor(int $userId, \DateTimeInterface $start, \DateTimeInterface $end, ?int $excludeId = null): array
    {
        return Shift::query()
            ->overlapping($userId, $start, $end)
            ->when($excludeId !== null, fn ($q) => $q->where('id', '!=', $excludeId))
            ->get()
            ->map(fn (Shift $s) => [
                'id' => (int) $s->id,
                'starts_at' => $s->starts_at->toIso8601String(),
                'ends_at' => $s->ends_at->toIso8601String(),
            ])
            ->all();
    }

    /**
     * Takvim verisi: aralıktaki vardiyalar + onaylı izinler + min. personel
     * uyarıları.
     *
     * @return array{shifts: mixed, leaves: mixed, warnings: array<int, array<string, mixed>>}
     */
    public function schedule(CarbonImmutable $from, CarbonImmutable $to, ?int $branchId = null, ?int $onlyUserId = null): array
    {
        $shifts = Shift::query()
            ->with('user:id,name,position')
            ->where('starts_at', '<', $to)
            ->where('ends_at', '>', $from)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->when($onlyUserId !== null, fn ($q) => $q->where('user_id', $onlyUserId))
            ->orderBy('starts_at')
            ->get();

        $leaves = LeaveRequest::query()
            ->with('user:id,name')
            ->where('status', LeaveRequest::STATUS_APPROVED)
            ->whereDate('starts_on', '<=', $to->toDateString())
            ->whereDate('ends_on', '>=', $from->toDateString())
            ->when($onlyUserId !== null, fn ($q) => $q->where('user_id', $onlyUserId))
            ->get();

        return [
            'shifts' => $shifts,
            'leaves' => $leaves,
            'warnings' => $onlyUserId === null ? $this->staffingWarnings($from, $to, $branchId, $shifts) : [],
        ];
    }

    /**
     * Minimum personel uyarıları: kural (şube+gün+pozisyon) altında kalan
     * günler listelenir.
     *
     * @param  \Illuminate\Support\Collection<int, Shift>  $shifts
     * @return array<int, array{date: string, branch_id: int, position: ?string, required: int, planned: int}>
     */
    public function staffingWarnings(CarbonImmutable $from, CarbonImmutable $to, ?int $branchId, $shifts): array
    {
        $rules = StaffingRule::query()
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->get();

        if ($rules->isEmpty()) {
            return [];
        }

        $warnings = [];

        for ($day = $from->startOfDay(); $day->lt($to); $day = $day->addDay()) {
            $weekday = ($day->dayOfWeekIso) - 1; // 0=Pzt … 6=Paz

            foreach ($rules as $rule) {
                if ($rule->weekday !== null && $rule->weekday !== $weekday) {
                    continue;
                }

                $planned = $shifts
                    ->filter(fn (Shift $s) => (int) $s->branch_id === (int) $rule->branch_id
                        && $s->starts_at->isSameDay($day)
                        && ($rule->position === null || mb_strtolower((string) $s->position) === mb_strtolower($rule->position)))
                    ->unique('user_id')
                    ->count();

                if ($planned < $rule->min_count) {
                    $warnings[] = [
                        'date' => $day->toDateString(),
                        'branch_id' => (int) $rule->branch_id,
                        'position' => $rule->position,
                        'required' => (int) $rule->min_count,
                        'planned' => $planned,
                    ];
                }
            }
        }

        return $warnings;
    }

    /** Değişim talebini onaylar: vardiya hedef personele devrolur. */
    public function approveSwap(ShiftSwapRequest $swap, User $decider, ?int $targetUserId = null, ?string $note = null): ShiftSwapRequest
    {
        if ($swap->status !== ShiftSwapRequest::STATUS_PENDING) {
            throw ValidationException::withMessages(['status' => ['Talep zaten sonuçlanmış.']]);
        }

        $targetId = $targetUserId ?? $swap->target_user_id;

        if ($targetId === null) {
            throw ValidationException::withMessages(['target_user_id' => ['Vardiyayı devralacak personel seçilmelidir.']]);
        }

        // Hedef personel aynı kiracıda ve aktif olmalı.
        $target = User::ofCurrentTenant()->where('is_active', true)->find($targetId);

        if ($target === null) {
            throw ValidationException::withMessages(['target_user_id' => ['Personel bulunamadı.']]);
        }

        return DB::transaction(function () use ($swap, $decider, $target, $note): ShiftSwapRequest {
            $shift = $swap->shift;

            // Devir çakışma yaratıyorsa onay reddedilir (uyarı olarak döner).
            $conflicts = $this->conflictsFor((int) $target->id, $shift->starts_at, $shift->ends_at, (int) $shift->id);

            if ($conflicts !== []) {
                throw ValidationException::withMessages([
                    'target_user_id' => ['Devralacak personelin aynı aralıkta vardiyası var.'],
                ]);
            }

            $shift->user_id = $target->id;
            $shift->save();

            $swap->forceFill([
                'status' => ShiftSwapRequest::STATUS_APPROVED,
                'target_user_id' => $target->id,
                'decided_by_id' => $decider->id,
                'decided_at' => now(),
                'decision_note' => $note,
            ])->save();

            return $swap;
        });
    }

    private function assertValidWindow(CarbonImmutable $start, CarbonImmutable $end): void
    {
        if ($end->lte($start)) {
            throw ValidationException::withMessages(['ends_at' => ['Bitiş, başlangıçtan sonra olmalıdır.']]);
        }

        if ($start->diffInHours($end) > 24) {
            throw ValidationException::withMessages(['ends_at' => ['Bir vardiya 24 saati aşamaz.']]);
        }
    }
}
