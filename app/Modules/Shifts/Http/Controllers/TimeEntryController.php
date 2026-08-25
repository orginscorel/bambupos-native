<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Shifts\Services\AttendanceService;
use App\Modules\Shifts\Services\TimeClockService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mesai kayıtları: liste, manuel düzeltme (nedenli + denetimli), onay,
 * devam özeti.
 */
class TimeEntryController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(
        private readonly TimeClockService $clock,
        private readonly AttendanceService $attendance,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $canViewAll = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        $query = TimeEntry::query()
            ->with(['user:id,name,position', 'branch:id,name', 'shift:id,starts_at,ends_at,break_min', 'breaks', 'device:id,name'])
            ->when(! $canViewAll, fn ($q) => $q->where('user_id', $user->id))
            ->when($canViewAll && $request->filled('user_id'), fn ($q) => $q->where('user_id', (int) $request->input('user_id')))
            // ŞUBE KAPSAMI: yalnız geçerli şubenin mesai kayıtları (yönetici).
            ->when($canViewAll, fn ($q) => $q->where('branch_id', $this->currentBranchId()))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')))
            ->when($request->filled('from'), fn ($q) => $q->where('clock_in_at', '>=', $request->date('from')))
            ->when($request->filled('to'), fn ($q) => $q->where('clock_in_at', '<', $request->date('to')?->addDay()))
            ->orderByDesc('clock_in_at');

        $page = $query->paginate(25);

        $page->getCollection()->transform(fn (TimeEntry $e) => [
            'id' => $e->id,
            'user' => $e->user?->only(['id', 'name', 'position']),
            'branch' => $e->branch?->only(['id', 'name']),
            'shift' => $e->shift === null ? null : [
                'id' => $e->shift->id,
                'starts_at' => $e->shift->starts_at->toIso8601String(),
                'ends_at' => $e->shift->ends_at->toIso8601String(),
            ],
            'clock_in_at' => $e->clock_in_at->toIso8601String(),
            'clock_out_at' => $e->clock_out_at?->toIso8601String(),
            'method_in' => $e->method_in,
            'method_out' => $e->method_out,
            'device' => $e->device?->only(['id', 'name']),
            'ip_in' => $canViewAll ? $e->ip_in : null,
            'ip_out' => $canViewAll ? $e->ip_out : null,
            'break_total_min' => $e->break_total_min,
            'worked_min' => $e->worked_min,
            'planned_min' => $e->planned_min,
            'overtime_min' => $e->overtime_min,
            'missing_min' => $e->missing_min,
            'late_min' => $e->late_min,
            'early_leave_min' => $e->early_leave_min,
            'status' => $e->status,
            'approved_at' => $e->approved_at?->toIso8601String(),
            'edited_at' => $e->edited_at?->toIso8601String(),
            'edit_reason' => $e->edit_reason,
        ]);

        return response()->json($page);
    }

    /** Manuel düzeltme — neden zorunlu; audit_logs'a düşer. */
    public function update(Request $request, TimeEntry $entry): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);
        // ŞUBE KAPSAMI (denetim #8): başka şubenin mesai kaydı düzeltilemez.
        abort_unless($entry->branch_id === $this->currentBranchId(), 404);

        $data = $request->validate([
            'clock_in_at' => ['sometimes', 'date'],
            'clock_out_at' => ['sometimes', 'date'],
            'break_total_min' => ['sometimes', 'integer', 'min:0', 'max:1440'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
        ]);

        $reason = $data['reason'];
        unset($data['reason']);

        $entry = $this->clock->correct($entry, $data, $reason, $request->user());

        return response()->json(['entry' => $entry->fresh('breaks')]);
    }

    public function approve(Request $request, TimeEntry $entry): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);
        // ŞUBE KAPSAMI (denetim #8): başka şubenin mesai kaydı onaylanamaz.
        abort_unless($entry->branch_id === $this->currentBranchId(), 404);

        $entry = $this->clock->approve($entry, $request->user());

        return response()->json(['entry' => $entry]);
    }

    /** Devam özeti (fazla mesai / eksik / geç / izin / devamsızlık). */
    public function attendanceSummary(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['required', 'date'],
            'to' => ['required', 'date', 'after:from'],
        ]);

        $user = $request->user();
        $canViewAll = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        return response()->json([
            'summary' => $this->attendance->summary(
                CarbonImmutable::parse($data['from']),
                CarbonImmutable::parse($data['to']),
                $canViewAll ? null : (int) $user->id,
                // ŞUBE KAPSAMI: yönetici yalnız geçerli şubenin devam özetini görür.
                $canViewAll ? $this->currentBranchId() : null,
            ),
        ]);
    }
}
