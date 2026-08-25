<?php

declare(strict_types=1);

namespace App\Modules\StaffTasks\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\StaffTasks\Models\StaffTask;
use App\Modules\StaffTasks\Services\StaffTaskService;
use App\Modules\Tenancy\Concerns\ScopesToBranch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Panel (yönetici) GÖREV API'si. İzin: `tasks.view` görüntüle, `tasks.assign`
 * yaz. Tüm sorgular tenant-scope'lu (BelongsToTenant) + ŞUBE KAPSAMI'yla
 * (BranchContext) süzülür; başka şubenin görevi ne listelenir ne değiştirilir.
 */
class StaffTaskAdminController extends Controller
{
    use ScopesToBranch;

    public function __construct(
        private readonly StaffTaskService $service,
    ) {
    }

    /** Liste + atanabilir personel. İzin: tasks.view VEYA tasks.assign. */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('tasks.view') || $user->hasPermission('tasks.assign'), 403);

        $branchId = $this->currentBranchId();

        $tasks = $this->scopedQuery($branchId)
            ->with(['assignedTo:id,first_name,last_name,position', 'createdBy:id,first_name,last_name'])
            ->orderByRaw("FIELD(status, 'open', 'in_progress', 'done')")
            ->orderByRaw('due_at IS NULL, due_at ASC')
            ->latest('id')
            ->get()
            ->map(fn (StaffTask $t): array => $this->service->toDto($t))
            ->all();

        // Atanabilir personel: aktif, aynı kiracı, geçerli şube (insan hesapları).
        $staff = User::ofCurrentTenant()
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->orderBy('first_name')
            ->get(['id', 'first_name', 'last_name', 'name', 'position'])
            ->map(fn (User $u): array => [
                'id' => (int) $u->getKey(),
                // `name` gerçek bir kolon (saving hook doldurur); kolon listesine
                // eklenmezse null döner → atama listesi boş görünür. first/last'tan
                // türetmeyi de yedek tut (ada göre eski/eksik kayıtlar için).
                'name' => $u->name ?: trim(($u->first_name ?? '').' '.($u->last_name ?? '')),
                'position' => $u->position,
            ])
            ->all();

        return response()->json(['tasks' => $tasks, 'staff' => $staff]);
    }

    /** Görev ata. İzin: tasks.assign. */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('tasks.assign'), 403);

        $data = $request->validate([
            'assigned_to_id' => ['required', 'integer'],
            'title' => ['required', 'string', 'max:160'],
            'description' => ['nullable', 'string'],
            'priority' => ['required', Rule::in(['low', 'normal', 'high'])],
            'due_at' => ['nullable', 'date'],
            'branch_id' => ['nullable', 'integer'],
        ]);

        // Atanan personel geçerli kiracı + şube içinde olmalı (şube sızıntısı yok).
        $branchId = $this->currentBranchId();
        $assigneeExists = User::ofCurrentTenant()
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->whereKey($data['assigned_to_id'])
            ->exists();
        abort_unless($assigneeExists, 422);

        // Şube: istekten gelen değere GÜVENME — verilirse doğrula, yoksa aktif şube.
        if (array_key_exists('branch_id', $data) && $data['branch_id'] !== null) {
            abort_unless($this->branchContext()->isAllowed((int) $data['branch_id']), 403);
            $data['branch_id'] = (int) $data['branch_id'];
        } else {
            $data['branch_id'] = $branchId;
        }

        $task = $this->service->assign($data, $user);

        return response()->json(['task' => $this->service->toDto($task->load(['assignedTo', 'createdBy']))], 201);
    }

    /** Görevi güncelle. İzin: tasks.assign. */
    public function update(Request $request, StaffTask $task): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('tasks.assign'), 403);
        $this->assertInScope($task);

        $data = $request->validate([
            'title' => ['sometimes', 'string', 'max:160'],
            'description' => ['sometimes', 'nullable', 'string'],
            'priority' => ['sometimes', Rule::in(['low', 'normal', 'high'])],
            'due_at' => ['sometimes', 'nullable', 'date'],
            'status' => ['sometimes', Rule::in(['open', 'in_progress', 'done'])],
        ]);

        $task = $this->service->updateTask($task, $data);

        return response()->json(['task' => $this->service->toDto($task->load(['assignedTo', 'createdBy']))]);
    }

    /** Görevi sil. İzin: tasks.assign. */
    public function destroy(Request $request, StaffTask $task): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('tasks.assign'), 403);
        $this->assertInScope($task);

        $task->delete();

        return response()->json(null, 204);
    }

    /**
     * Geçerli şubeye süzülmüş sorgu. Şubesiz (branch_id null) görevler
     * tenant genelindedir; aktif şube listesinde de görünür.
     */
    private function scopedQuery(?int $branchId)
    {
        return StaffTask::query()
            ->when($branchId !== null, fn ($q) => $q->where(function ($w) use ($branchId): void {
                $w->where('branch_id', $branchId)->orWhereNull('branch_id');
            }));
    }

    /** Görev geçerli şube kapsamında değilse 404 (sızıntı yok). */
    private function assertInScope(StaffTask $task): void
    {
        $branchId = $this->currentBranchId();

        if ($branchId !== null
            && $task->branch_id !== null
            && (int) $task->branch_id !== $branchId) {
            abort(404);
        }
    }
}
