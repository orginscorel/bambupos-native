<?php

namespace App\Modules\Reservations\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Reservations\Enums\WaitlistStatus;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Database\Factories\WaitlistEntryFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Bekleme listesi girdisi (Faz-9). */
class WaitlistEntry extends Model
{
    /** @use HasFactory<WaitlistEntryFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'customer_name',
        'customer_phone',
        'party_size',
        'note',
        'status',
        'quoted_wait_minutes',
        'source',
    ];

    protected function casts(): array
    {
        return [
            'party_size' => 'integer',
            'quoted_wait_minutes' => 'integer',
            'status' => WaitlistStatus::class,
            'notified_at' => 'datetime',
            'seated_at' => 'datetime',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function reservation(): BelongsTo
    {
        return $this->belongsTo(Reservation::class);
    }

    /** Açık (bekleyen/çağrılan) girdiler. */
    public function scopeOpen(Builder $query): Builder
    {
        return $query->whereIn('status', [WaitlistStatus::Waiting->value, WaitlistStatus::Notified->value]);
    }

    protected static function newFactory(): Factory
    {
        return WaitlistEntryFactory::new();
    }
}
