<?php

declare(strict_types=1);

namespace App\Modules\StaffTasks\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\StaffTasks\Models\StaffTask;
use App\Modules\StaffTasks\Services\StaffTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Portal "Görevlerim" (self-servis). Kişi YALNIZ kendine atanmış görevleri
 * görür ve durumunu ilerletir (in_progress / done). İzin gerekmez; oturum
 * yeterli. Başkasının görevine erişim 404 (sızıntı yok).
 */
class PortalTaskController extends Controller
{
    public function __construct(
        private readonly StaffTaskService $service,
    ) {
    }

    /** Kişinin kendi görevleri + durum sayaçları. */
    public function index(Request $request): JsonResponse
    {
        $userId = (int) $request->user()->getKey();

        $tasks = StaffTask::query()
            ->where('assigned_to_id', $userId)
            ->with(['assignedTo:id,first_name,last_name,position', 'createdBy:id,first_name,last_name'])
            ->orderByRaw("FIELD(status, 'open', 'in_progress', 'done')")
            ->orderByRaw('due_at IS NULL, due_at ASC')
            ->latest('id')
            ->get();

        $counts = [
            'open' => $tasks->where('status', 'open')->count(),
            'in_progress' => $tasks->where('status', 'in_progress')->count(),
            'done' => $tasks->where('status', 'done')->count(),
        ];

        return response()->json([
            'tasks' => $tasks->map(fn (StaffTask $t): array => $this->service->toDto($t))->all(),
            'counts' => $counts,
        ]);
    }

    /**
     * Kendi görevinin durumunu güncelle. done → completed_at damgalanır.
     * Başkasının görevi 404.
     */
    public function updateStatus(Request $request, StaffTask $task): JsonResponse
    {
        $userId = (int) $request->user()->getKey();
        abort_unless((int) $task->assigned_to_id === $userId, 404);

        $data = $request->validate([
            'status' => ['required', Rule::in(['in_progress', 'done'])],
        ]);

        // Durum makinesi: yalnız İLERİ geçiş. open → in_progress → done tek
        // yönlüdür; tamamlanan görev personel tarafından yeniden AÇILAMAZ
        // (done → * yasak). Yönetici geri alabilir (StaffTaskAdminController).
        $rank = ['open' => 0, 'in_progress' => 1, 'done' => 2];
        $current = $rank[(string) $task->status] ?? 0;
        $next = $rank[$data['status']];

        abort_if((string) $task->status === 'done', 422, 'Tamamlanan görev yeniden açılamaz.');
        abort_if($next <= $current, 422, 'Görev durumu yalnızca ileri alınabilir.');

        $task->status = $data['status'];
        $task->completed_at = $data['status'] === 'done' ? now() : null;
        $task->save();

        return response()->json(['task' => $this->service->toDto($task->load(['assignedTo', 'createdBy']))]);
    }
}
