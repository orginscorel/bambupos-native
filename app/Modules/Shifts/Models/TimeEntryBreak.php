<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Mola başlangıç/bitiş çifti. */
class TimeEntryBreak extends Model
{
    use BelongsToTenant;

    protected $fillable = ['time_entry_id', 'started_at', 'ended_at'];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
        ];
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
