<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * İzin / rapor / tatil / devamsızlık kaydı.
 * 'absence' (devamsızlık) yönetici tarafından kayıt olarak açılır.
 */
class LeaveRequest extends Model
{
    use Auditable, BelongsToTenant;

    public const TYPES = ['annual', 'sick', 'unpaid', 'holiday', 'absence', 'other'];

    public const TYPE_LABELS = [
        'annual' => 'Yıllık izin',
        'sick' => 'Rapor',
        'unpaid' => 'Ücretsiz izin',
        'holiday' => 'Resmî tatil',
        'absence' => 'Devamsızlık',
        'other' => 'Diğer',
    ];

    public const STATUS_PENDING = 'pending';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_REJECTED = 'rejected';

    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = ['branch_id', 'user_id', 'type', 'starts_on', 'ends_on', 'reason', 'status'];

    protected function casts(): array
    {
        return [
            'starts_on' => 'date',
            'ends_on' => 'date',
            'decided_at' => 'datetime',
        ];
    }

    /** Kapsanan gün sayısı (uçlar dahil). */
    public function days(): int
    {
        return (int) $this->starts_on->diffInDays($this->ends_on) + 1;
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function decidedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'decided_by_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_id');
    }
}
