<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Planlanan vardiya. Tekrarlayan vardiyalar ayrı satırlar olarak üretilir
 * ve repeat_group (uuid) ile birbirine bağlanır.
 */
class Shift extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'branch_id',
        'user_id',
        'position',
        'starts_at',
        'ends_at',
        'break_min',
        'note',
        'repeat_group',
    ];

    protected function casts(): array
    {
        return [
            'starts_at' => 'datetime',
            'ends_at' => 'datetime',
            'break_min' => 'integer',
        ];
    }

    /** Planlanan net çalışma süresi (dakika, mola düşülmüş). */
    public function plannedMinutes(): int
    {
        $gross = (int) $this->starts_at->diffInMinutes($this->ends_at);

        return max(0, $gross - (int) $this->break_min);
    }

    /** Verilen aralıkla çakışan vardiyalar (aynı personel). */
    public function scopeOverlapping(Builder $query, int $userId, \DateTimeInterface $start, \DateTimeInterface $end): Builder
    {
        return $query
            ->where('user_id', $userId)
            ->where('starts_at', '<', $end)
            ->where('ends_at', '>', $start);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_id');
    }

    public function swapRequests(): HasMany
    {
        return $this->hasMany(ShiftSwapRequest::class);
    }
}
