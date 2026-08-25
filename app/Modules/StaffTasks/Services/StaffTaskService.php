<?php

declare(strict_types=1);

namespace App\Modules\StaffTasks\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Notify\Enums\NotificationType;
use App\Modules\Notify\Services\NotificationDispatcher;
use App\Modules\StaffTasks\Models\StaffTask;

/**
 * GÖREV iş kuralları: atama, güncelleme ve API sunumu (DTO).
 *
 * Atama akışında görev kaydı BİRİNCİLDİR: bildirim (TaskAssigned) yalnızca
 * best-effort ek adımdır; hata olsa da görev kaydı başarılı sayılır (try/catch
 * ile yutulur). tenant_id BelongsToTenant ile bağlamdan otomatik atanır.
 */
class StaffTaskService
{
    public function __construct(
        private readonly NotificationDispatcher $dispatcher,
    ) {
    }

    /**
     * Yeni görev ata (created_by = actor). Kaydeder, sonra atanan personele
     * TaskAssigned bildirimi gönderir (best-effort).
     *
     * @param  array<string, mixed>  $data  assigned_to_id,title,description?,priority,due_at?,branch_id?
     */
    public function assign(array $data, User $actor): StaffTask
    {
        $task = new StaffTask([
            'branch_id' => $data['branch_id'] ?? null,
            'assigned_to_id' => (int) $data['assigned_to_id'],
            'title' => (string) $data['title'],
            'description' => $data['description'] ?? null,
            'priority' => $data['priority'] ?? 'normal',
            'status' => 'open',
            'due_at' => $data['due_at'] ?? null,
        ]);
        // tenant_id fillable DEĞİL → bağlamdan (BelongsToTenant) atanır.
        $task->created_by_id = (int) $actor->getKey();
        $task->save();

        $this->notifyAssigned($task);

        return $task;
    }

    /**
     * Görevi güncelle (yönetici). status 'done' olduğunda completed_at damgalanır;
     * done'dan çıkarsa temizlenir.
     *
     * @param  array<string, mixed>  $data  title?,description?,priority?,due_at?,status?
     */
    public function updateTask(StaffTask $task, array $data): StaffTask
    {
        $task->fill($data);

        if (array_key_exists('status', $data)) {
            if ($data['status'] === 'done') {
                // done'a İLK geçişte damgala; zaten done ise özgün tamamlanma
                // zamanını KORU (yönetici başka alanı güncellerken kaymasın).
                $task->completed_at = $task->completed_at ?? now();
            } else {
                // done'dan çıkınca (geri alma) tamamlanma damgası temizlenir.
                $task->completed_at = null;
            }
        }

        $task->save();

        return $task;
    }

    /**
     * API sunumu (TaskDTO). Tarihler ISO-8601; atanan/atayan iç içe nesne.
     *
     * @return array<string, mixed>
     */
    public function toDto(StaffTask $task): array
    {
        $assignee = $task->assignedTo;
        $creator = $task->createdBy;

        return [
            'id' => (int) $task->getKey(),
            'title' => $task->title,
            'description' => $task->description,
            'priority' => $task->priority,
            'status' => $task->status,
            'due_at' => $task->due_at?->toIso8601String(),
            'branch_id' => $task->branch_id !== null ? (int) $task->branch_id : null,
            'assigned_to' => $assignee !== null ? [
                'id' => (int) $assignee->getKey(),
                'name' => $assignee->name,
                'position' => $assignee->position,
            ] : null,
            'created_by' => $creator !== null ? [
                'id' => (int) $creator->getKey(),
                'name' => $creator->name,
            ] : null,
            'created_at' => $task->created_at?->toIso8601String(),
            'completed_at' => $task->completed_at?->toIso8601String(),
        ];
    }

    /** Atama bildirimi — best-effort (görev kaydını asla düşürmez). */
    private function notifyAssigned(StaffTask $task): void
    {
        try {
            if ($task->tenant_id === null) {
                return;
            }

            $this->dispatcher->notify(NotificationType::TaskAssigned, [
                'tenant_id' => (int) $task->tenant_id,
                'branch_id' => $task->branch_id !== null ? (int) $task->branch_id : null,
                'title' => 'Yeni görev: '.$task->title,
                'body' => $task->description ?: 'Sana yeni bir görev atandı.',
                'data' => ['task_id' => (int) $task->getKey(), 'url' => '/gorevlerim'],
                // TaskAssigned targetPermissions=[] + includeManagers=false →
                // YALNIZ atanan personel (extra_user_ids) bildirim alır.
                'extra_user_ids' => [(int) $task->assigned_to_id],
                'dedup_key' => 'task:'.$task->getKey(),
            ]);
        } catch (\Throwable) {
            // yut — görev kaydı bildirimsiz de başarılı olsun
        }
    }
}
