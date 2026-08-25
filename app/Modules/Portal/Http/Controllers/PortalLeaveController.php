<?php

declare(strict_types=1);

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\Shifts\Models\LeaveRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Portal "İzinlerim": kişinin KENDİ izin/rapor taleplerini görme, açma ve
 * bekleyen talebini geri çekme — self-servis, oturum yeter (PIN'siz, ek izin
 * gerektirmez). Devamsızlık ('absence') ve resmî tatil ('holiday') buradan
 * AÇILAMAZ — onlar yönetici işidir (LeaveRequestController). Talep açılınca §8
 * NotifyEmitter deseninde yöneticilere (staff.manage) bildirim gider.
 */
class PortalLeaveController extends Controller
{
    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
    ) {
    }

    /** Kişinin KENDİ izin talepleri — en yeni önce. */
    public function index(Request $request): JsonResponse
    {
        $requests = LeaveRequest::query()
            ->where('user_id', $request->user()->id)
            ->orderByDesc('id')
            ->get()
            ->map(fn (LeaveRequest $leave) => $this->present($leave))
            ->values();

        return response()->json(['requests' => $requests]);
    }

    /** Yeni izin/rapor talebi aç (kendi adına, pending). */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();

        // absence/holiday YASAK — yalnız yönetici açar.
        $data = $request->validate([
            'type' => ['required', 'in:annual,sick,unpaid,other'],
            'starts_on' => ['required', 'date'],
            'ends_on' => ['required', 'date', 'after_or_equal:starts_on'],
            'reason' => ['required', 'string', 'max:500'],
        ]);

        $leave = new LeaveRequest([
            // tenant_id BelongsToTenant ile otomatik; branch kullanıcının şubesi (varsa).
            'branch_id' => $user->branch_id !== null ? (int) $user->branch_id : null,
            'user_id' => (int) $user->id,
            'type' => $data['type'],
            'starts_on' => $data['starts_on'],
            'ends_on' => $data['ends_on'],
            'reason' => $data['reason'],
            'status' => LeaveRequest::STATUS_PENDING,
        ]);
        $leave->created_by_id = $user->id;
        $leave->save();

        // §8: onaylayabilen yöneticilere bildir — best-effort (ana akış düşmez).
        try {
            $label = LeaveRequest::TYPE_LABELS[$leave->type] ?? $leave->type;
            $range = $leave->starts_on->format('d.m.Y').' – '.$leave->ends_on->format('d.m.Y');

            $this->dispatcher->notify(NotificationType::LeaveRequested, [
                'tenant_id' => (int) $leave->tenant_id,
                'branch_id' => $leave->branch_id !== null ? (int) $leave->branch_id : null,
                'title' => 'İzin talebi: '.$user->name,
                'body' => $label.' · '.$range,
                'data' => ['url' => '/panel/vardiya/izinler'],
                'dedup_key' => 'leave:'.$leave->id,
            ]);
        } catch (\Throwable) {
            // yut — izin talebi akışı bildirim yüzünden bozulmaz
        }

        return response()->json(['request' => $this->present($leave)]);
    }

    /** Kişi kendi BEKLEYEN talebini geri çeker. */
    public function cancel(Request $request, LeaveRequest $leave): JsonResponse
    {
        // Route-model-binding tenant-scope'lu; yine de sahiplik kesin doğrulanır.
        abort_unless((int) $leave->user_id === (int) $request->user()->id, 403);
        abort_unless($leave->status === LeaveRequest::STATUS_PENDING, 422);

        $leave->status = LeaveRequest::STATUS_CANCELLED;
        $leave->save();

        return response()->json(['request' => $this->present($leave)]);
    }

    /**
     * Tek talebin portal sunumu.
     *
     * @return array<string, mixed>
     */
    private function present(LeaveRequest $leave): array
    {
        return [
            'id' => (int) $leave->id,
            'type' => $leave->type,
            'type_label' => LeaveRequest::TYPE_LABELS[$leave->type] ?? $leave->type,
            'starts_on' => $leave->starts_on->format('Y-m-d'),
            'ends_on' => $leave->ends_on->format('Y-m-d'),
            'days' => $leave->days(),
            'reason' => $leave->reason,
            'status' => $leave->status,
            'status_label' => $this->statusLabel($leave->status),
            'created_at' => $leave->created_at?->toIso8601String(),
            'decided_at' => $leave->decided_at?->toIso8601String(),
        ];
    }

    /** Durum → Türkçe etiket. */
    private function statusLabel(string $status): string
    {
        return match ($status) {
            LeaveRequest::STATUS_PENDING => 'Beklemede',
            LeaveRequest::STATUS_APPROVED => 'Onaylandı',
            LeaveRequest::STATUS_REJECTED => 'Reddedildi',
            LeaveRequest::STATUS_CANCELLED => 'İptal',
            default => $status,
        };
    }
}
