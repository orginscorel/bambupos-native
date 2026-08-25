<?php

declare(strict_types=1);

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
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
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $canViewAll = $user->hasPermission('staff.view') || $user->hasPermission('staff.manage');

        $query = LeaveRequest::query()
            ->with(['user:id,name,position', 'decidedBy:id,name', 'createdBy:id,name'])
            ->when(! $canViewAll, fn ($q) => $q->where('user_id', $user->id))
            // ŞUBE KAPSAMI (denetim #8): yönetici yalnız kendi şubesinin izinlerini görür.
            ->when($canViewAll, fn ($q) => $q->where('branch_id', $this->currentBranchId()))
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

        // §8 (denetim orta): personel kendi talebini açtıysa YÖNETİCİ haberdar edilir
        // (LeaveRequested → targetPermissions=['staff.manage']). Yönetici zaten onaylı
        // açtıysa bildirime gerek yok. Best-effort — talep kaydı bildirimsiz de geçerli.
        if ($leave->status === LeaveRequest::STATUS_PENDING) {
            $this->notifyRequested($leave);
        }

        return response()->json(['leave' => $leave->load('user:id,name')], 201);
    }

    /** Yeni izin talebini şube yöneticilerine bildir (karar bekliyor). */
    private function notifyRequested(LeaveRequest $leave): void
    {
        try {
            $label = LeaveRequest::TYPE_LABELS[$leave->type] ?? $leave->type;
            $range = $leave->starts_on->format('d.m.Y').' – '.$leave->ends_on->format('d.m.Y');
            $who = $leave->user()->value('name') ?? 'Personel';

            $this->dispatcher->notify(NotificationType::LeaveRequested, [
                'tenant_id' => (int) $leave->tenant_id,
                'branch_id' => $leave->branch_id !== null ? (int) $leave->branch_id : null,
                'title' => 'Yeni izin talebi',
                'body' => $who.' · '.$label.' · '.$range,
                'data' => ['url' => '/panel/mesai/talepler'],
                'dedup_key' => 'leave_requested:'.$leave->id,
            ]);
        } catch (\Throwable) {
            // yut — talep bildirimsiz de geçerlidir
        }
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
        $isOwner = (int) $leave->user_id === (int) $user->id;

        abort_unless($isOwner || $user->hasPermission('staff.manage'), 403);
        // Sahibi kendi talebini iptal edebilir; yönetici YALNIZ kendi şubesinde (denetim #8).
        abort_unless($isOwner || $leave->branch_id === $this->currentBranchId(), 404);
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
        // ŞUBE KAPSAMI (denetim #8): başka şubenin izin talebi karara bağlanamaz.
        abort_unless($leave->branch_id === $this->currentBranchId(), 404);
        abort_unless($leave->status === LeaveRequest::STATUS_PENDING, 422);

        $data = $request->validate(['note' => ['nullable', 'string', 'max:255']]);

        $leave->forceFill([
            'status' => $status,
            'decided_by_id' => $request->user()->id,
            'decided_at' => now(),
            'decision_note' => $data['note'] ?? null,
        ])->save();

        // §8: karar TALEP SAHİBİNE bildirilir — best-effort (karar akışı düşmez).
        $this->notifyDecided($leave, $status);

        return response()->json(['leave' => $leave->fresh(['user:id,name', 'decidedBy:id,name'])]);
    }

    /**
     * İzin kararını (onay/ret) yalnız TALEP SAHİBİNE bildir. LeaveDecided
     * targetPermissions=[] + includeManagers=false → extra_user_ids ile hedeflenen
     * talep sahibi dışında kimse almaz. Bildirim ek adımdır; hata yutulur.
     */
    private function notifyDecided(LeaveRequest $leave, string $status): void
    {
        try {
            $approved = $status === LeaveRequest::STATUS_APPROVED;
            $label = LeaveRequest::TYPE_LABELS[$leave->type] ?? $leave->type;
            $range = $leave->starts_on->format('d.m.Y').' – '.$leave->ends_on->format('d.m.Y');

            $this->dispatcher->notify(NotificationType::LeaveDecided, [
                'tenant_id' => (int) $leave->tenant_id,
                'branch_id' => $leave->branch_id !== null ? (int) $leave->branch_id : null,
                'title' => $approved ? 'İzniniz onaylandı' : 'İzniniz reddedildi',
                'body' => $label.' · '.$range,
                'data' => ['url' => '/takvim'],
                'extra_user_ids' => [(int) $leave->user_id],
                'dedup_key' => 'leave_decided:'.$leave->id.':'.$status,
            ]);
        } catch (\Throwable) {
            // yut — karar kaydı bildirimsiz de geçerlidir
        }
    }
}
