<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Mesai kaydı (giriş/çıkış). Hesaplanan alanlar (worked/overtime/late…)
 * yalnız TimeClockService tarafından yazılır.
 *
 * Auditable trait'i BİLİNÇLİ kullanılmaz: her giriş/çıkış audit'e gürültü
 * yazmasın; manuel düzeltme ve onay TimeClockService'te AÇIKÇA loglanır.
 */
class TimeEntry extends Model
{
    use BelongsToTenant;

    public const STATUS_OPEN = 'open';

    public const STATUS_CLOSED = 'closed';

    protected $fillable = [
        'branch_id',
        'user_id',
        'shift_id',
        'clock_in_at',
        'clock_out_at',
        'method_in',
        'method_out',
        'device_id',
        'ip_in',
        'ip_out',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'clock_in_at' => 'datetime',
            'clock_out_at' => 'datetime',
            'approved_at' => 'datetime',
            'edited_at' => 'datetime',
            'break_total_min' => 'integer',
            'worked_min' => 'integer',
            'planned_min' => 'integer',
            'overtime_min' => 'integer',
            'missing_min' => 'integer',
            'late_min' => 'integer',
            'early_leave_min' => 'integer',
            'lat_in' => 'float',
            'lng_in' => 'float',
            'lat_out' => 'float',
            'lng_out' => 'float',
        ];
    }

    public function isOpen(): bool
    {
        return $this->status === self::STATUS_OPEN;
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function shift(): BelongsTo
    {
        return $this->belongsTo(Shift::class);
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(ClockDevice::class, 'device_id');
    }

    public function breaks(): HasMany
    {
        return $this->hasMany(TimeEntryBreak::class)->orderBy('id');
    }

    public function openBreak(): ?TimeEntryBreak
    {
        return $this->breaks()->whereNull('ended_at')->first();
    }
}
