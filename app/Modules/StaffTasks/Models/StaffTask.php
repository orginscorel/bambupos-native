<?php

declare(strict_types=1);

namespace App\Modules\StaffTasks\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Personel görevi (staff_tasks). Kiracıya ait (BelongsToTenant) + şube
 * kapsamlı. Yönetici atar (created_by_id), personel üstlenir (assigned_to_id)
 * ve durumunu ilerletir (open → in_progress → done).
 *
 * tenant_id BİLİNÇLİ olarak fillable DEĞİL (BelongsToTenant; bağlamdan atanır).
 */
class StaffTask extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'branch_id',
        'assigned_to_id',
        'title',
        'description',
        'priority',
        'status',
        'due_at',
        'created_by_id',
        'completed_at',
    ];

    protected function casts(): array
    {
        return [
            'due_at' => 'datetime',
            'completed_at' => 'datetime',
        ];
    }

    /* ---------------- İlişkiler ---------------- */

    /** Görevi üstlenen personel. */
    public function assignedTo(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assigned_to_id');
    }

    /** Görevi atayan yönetici (nullable). */
    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_id');
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
