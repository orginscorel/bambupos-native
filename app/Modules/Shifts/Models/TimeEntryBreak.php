<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Mola başlangıç/bitiş çifti (tür: normal mola / tuvalet molası). */
class TimeEntryBreak extends Model
{
    use BelongsToTenant;

    public const KIND_BREAK = 'break';

    public const KIND_TOILET = 'toilet';

    protected $fillable = ['time_entry_id', 'kind', 'started_at', 'ended_at'];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
    }

    /** Tuvalet molası mı? (aksi hâlde normal mola) */
    public function isToilet(): bool
    {
        return $this->kind === self::KIND_TOILET;
    }

    public function kindLabel(): string
    {
        return $this->isToilet() ? 'Tuvalet molası' : 'Mola';
    }

    public function minutes(): int
    {
        if ($this->ended_at === null) {
            return 0;
        }

        return max(0, (int) $this->started_at->diffInMinutes($this->ended_at));
    }

    public function timeEntry(): BelongsTo
    {
        return $this->belongsTo(TimeEntry::class);
    }
}
