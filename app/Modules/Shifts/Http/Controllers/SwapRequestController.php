<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\ShiftSwapRequest;
use App\Modules\Shifts\Services\ShiftPlanner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Vardiya değişim talepleri: sahibi açar/iptal eder; yönetici onaylar/reddeder.
 */
class SwapRequestController extends Controller
{
    public function __construct(private readonly ShiftPlanner $planner)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $canManage = $user->hasPermission('staff.manage');

        $query = ShiftSwapRequest::query()
            ->with(['shift.user:id,name', 'shift.branch:id,name', 'requestedBy:id,name', 'targetUser:id,name', 'decidedBy:id,name'])
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')))
            ->when(! $canManage, fn ($q) => $q->where(fn ($w) => $w
                ->where('requested_by_id', $user->id)
                ->orWhere('target_user_id', $user->id)))
            ->orderByDesc('id');

        return response()->json($query->paginate(25));
    }

    /** Vardiya sahibi (veya yönetici) değişim talebi açar. */
    public function store(Request $request, Shift $shift): JsonResponse
    {
        $user = $request->user();

        abort_unless(
            (int) $shift->user_id === (int) $user->id || $user->hasPermission('staff.manage'),
            403,
        );

        $data = $request->validate([
            'target_user_id' => ['nullable', 'integer'],
            'reason' => ['nullable', 'string', 'max:255'],
        ]);

        if (isset($data['target_user_id'])) {
            abort_unless(
                User::ofCurrentTenant()->where('is_active', true)->whereKey($data['target_user_id'])->exists(),
                404,
            );
        }

        // Aynı vardiya için bekleyen ikinci talep açılmaz.
        abort_if(
            $shift->swapRequests()->where('status', ShiftSwapRequest::STATUS_PENDING)->exists(),
            422,
            'Bu vardiya için zaten bekleyen bir talep var.',
        );

        $swap = new ShiftSwapRequest([
            'shift_id' => $shift->id,
            'target_user_id' => $data['target_user_id'] ?? null,
            'reason' => $data['reason'] ?? null,
            'status' => ShiftSwapRequest::STATUS_PENDING,
        ]);
        $swap->requested_by_id = $shift->user_id; // talep vardiya sahibi adınadır
        $swap->save();

        return response()->json(['swap' => $swap], 201);
    }

    public function approve(Request $request, ShiftSwapRequest $swap): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);

        $data = $request->validate([
            'target_user_id' => ['nullable', 'integer'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        $swap = $this->planner->approveSwap(
            $swap,
            $request->user(),
            isset($data['target_user_id']) ? (int) $data['target_user_id'] : null,
            $data['note'] ?? null,
        );

        return response()->json(['swap' => $swap->fresh(['shift', 'targetUser:id,name'])]);
    }

    public function reject(Request $request, ShiftSwapRequest $swap): JsonResponse
    {
        abort_unless($request->user()->hasPermission('staff.manage'), 403);
        abort_unless($swap->status === ShiftSwapRequest::STATUS_PENDING, 422);

        $data = $request->validate(['note' => ['nullable', 'string', 'max:255']]);

        $swap->forceFill([
            'status' => ShiftSwapRequest::STATUS_REJECTED,
            'decided_by_id' => $request->user()->id,
            'decided_at' => now(),
            'decision_note' => $data['note'] ?? null,
        ])->save();

        return response()->json(['swap' => $swap]);
    }

    /** Talep sahibi bekleyen talebini geri çeker. */
    public function cancel(Request $request, ShiftSwapRequest $swap): JsonResponse
    {
        $user = $request->user();

        abort_unless(
            (int) $swap->requested_by_id === (int) $user->id || $user->hasPermission('staff.manage'),
            403,
        );
        abort_unless($swap->status === ShiftSwapRequest::STATUS_PENDING, 422);

        $swap->forceFill([
            'status' => ShiftSwapRequest::STATUS_CANCELLED,
            'decided_by_id' => $user->id,
            'decided_at' => now(),
        ])->save();

        return response()->json(['swap' => $swap]);
    }
}
