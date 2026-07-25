<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\LeaveRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * İzin / rapor / tatil / devamsızlık kayıtları.
 * Personel kendi talebini açar; yönetici başkası adına kayıt açabilir
 * (ör. devamsızlık) ve karar verir.
 */
class LeaveRequestController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $canViewAll = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        $query = LeaveRequest::query()
            ->with(['user:id,name,position', 'decidedBy:id,name', 'createdBy:id,name'])
            ->when(! $canViewAll, fn ($q) => $q->where('user_id', $user->id))
            ->when($canViewAll && $request->filled('user_id'), fn ($q) => $q->where('user_id', (int) $request->input('user_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')))
            ->when($request->filled('type'), fn ($q) => $q->where('type', $request->string('type')))
            ->orderByDesc('id');

        return response()->json($query->paginate(25));
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        $canManage = $user->hasPermission('staff.manage');

        $data = $request->validate([
            'user_id' => ['nullable', 'integer'],
            'type' => ['required', 'in:'.implode(',', LeaveRequest::TYPES)],
            'starts_on' => ['required', 'date'],
            'ends_on' => ['required', 'date', 'after_or_equal:starts_on'],
            'reason' => ['nullable', 'string', 'max:255'],
        ]);

        $targetId = isset($data['user_id']) ? (int) $data['user_id'] : (int) $user->id;

        // Başkası adına kayıt (ve devamsızlık türü) yalnız yönetici.
        abort_unless($targetId === (int) $user->id || $canManage, 403);
        abort_unless($data['type'] !== 'absence' || $canManage, 403);

        $target = User::ofCurrentTenant()->whereKey($targetId)->first();
        abort_if($target === null, 404);

        $leave = new LeaveRequest([
            'branch_id' => $target->branch_id,
            'user_id' => $target->id,
            'type' => $data['type'],
            'starts_on' => $data['starts_on'],
            'ends_on' => $data['ends_on'],
            'reason' => $data['reason'] ?? null,
            // Yönetici kaydı (devamsızlık/tatil) doğrudan onaylıdır.
            'status' => $canManage && $targetId !== (int) $user->id
                ? LeaveRequest::STATUS_APPROVED
                : LeaveRequest::STATUS_PENDING,
        ]);
        $leave->created_by_id = $user->id;

        if ($leave->status === LeaveRequest::STATUS_APPROVED) {
            $leave->decided_by_id = $user->id;
            $leave->decided_at = now();
        }

        $leave->save();

        return response()->json(['leave' => $leave->load('user:id,name')], 201);
    }

    public function approve(Request $request, LeaveRequest $leave): JsonResponse
    {
        return $this->decide($request, $leave, LeaveRequest::STATUS_APPROVED);
    }

    public function reject(Request $request, LeaveRequest $leave): JsonResponse
    {
        return $this->decide($request, $leave, LeaveRequest::STATUS_REJECTED);
    }

    /** Talep sahibi bekleyen talebini geri çeker. */
    public function cancel(Request $request, LeaveRequest $leave): JsonResponse
    {
        $user = $request->user();

        abort_unless(
            (int) $leave->user_id === (int) $user->id || $user->hasPermission('staff.manage'),
            403,
        );
        abort_unless($leave->status === LeaveRequest::STATUS_PENDING, 422);

        $leave->forceFill([
            'status' => LeaveRequest::STATUS_CANCELLED,
            'decided_by_id' => $user->id,
            'decided_at' => now(),
        ])->save();

        return response()->json(['leave' => $leave]);
    }

    private function decide(Request $request, LeaveRequest $leave, string $status): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);
        abort_unless($leave->status === LeaveRequest::STATUS_PENDING, 422);

        $data = $request->validate(['note' => ['nullable', 'string', 'max:255']]);

        $leave->forceFill([
            'status' => $status,
            'decided_by_id' => $request->user()->id,
            'decided_at' => now(),
            'decision_note' => $data['note'] ?? null,
        ])->save();

        return response()->json(['leave' => $leave->fresh(['user:id,name', 'decidedBy:id,name'])]);
    }
}
