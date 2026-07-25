<?php

namespace App\Modules\Reservations\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Reservations\Enums\DepositStatus;
use App\Modules\Reservations\Enums\ReservationSource;
use App\Modules\Reservations\Enums\ReservationStatus;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Models\Area;
use Database\Factories\ReservationFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Carbon;

/**
 * Rezervasyon (Faz-9). Masa ataması pivot üzerinden (birleştirme = çoklu
 * masa). allergy_note HASSAS: yalnız reservations.view_sensitive izniyle
 * sunulur (ReservationPresenter) ve denetim kaydında maskelenir.
 */
class Reservation extends Model
{
    /** @use HasFactory<ReservationFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'customer_name',
        'customer_phone',
        'customer_email',
        'reserved_at',
        'duration_minutes',
        'buffer_minutes',
        'party_size',
        'area_id',
        'special_note',
        'allergy_note',
        'occasion',
        'occasion_note',
        'deposit_minor',
        'deposit_status',
        'source',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'reserved_at' => \App\Modules\Reservations\Casts\BranchLocalDateTime::class,
            'duration_minutes' => 'integer',
            'buffer_minutes' => 'integer',
            'party_size' => 'integer',
            'deposit_minor' => 'integer',
            'deposit_status' => DepositStatus::class,
            'source' => ReservationSource::class,
            'status' => ReservationStatus::class,
            'confirmed_at' => 'datetime',
            'arrived_at' => 'datetime',
            'seated_at' => 'datetime',
            'completed_at' => 'datetime',
            'cancelled_at' => 'datetime',
            'reminder_sent_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (self $reservation): void {
            $reservation->confirmation_token ??= bin2hex(random_bytes(20)); // 40 hex
        });
    }

    /* ---------------- İlişkiler ---------------- */

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function area(): BelongsTo
    {
        return $this->belongsTo(Area::class, 'area_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function tables(): BelongsToMany
    {
        return $this->belongsToMany(Table::class, 'reservation_tables', 'reservation_id', 'table_id');
    }

    /* ---------------- Zaman pencereleri ---------------- */

    public function startsAt(): Carbon
    {
        return $this->reserved_at->copy();
    }

    /**
     * Şube saat dilimindeki (müşteriye/personele gösterilen) başlangıç.
     * Saklama UTC'dir (app.timezone); giriş de şube diliminde yorumlanır —
     * ReservationService::parseBranchTime.
     */
    public function localReservedAt(): Carbon
    {
        $tz = $this->branch?->timezone ?: config('app.timezone');

        return $this->reserved_at->copy()->setTimezone($tz);
    }

    /** Masanın dolu sayıldığı bitiş (süre dahil, tampon HARİÇ). */
    public function endsAt(): Carbon
    {
        return $this->reserved_at->copy()->addMinutes((int) $this->duration_minutes);
    }

    /** Tampon (temizlik/hazırlık) dahil blokaj bitişi. */
    public function blocksUntil(): Carbon
    {
        return $this->endsAt()->addMinutes((int) $this->buffer_minutes);
    }

    /* ---------------- Scope'lar ---------------- */

    /** Yer tutan (kapanmamış) rezervasyonlar. */
    public function scopeBlocking(Builder $query): Builder
    {
        return $query->whereIn('status', ReservationStatus::blockingValues());
    }

    protected static function newFactory(): Factory
    {
        return ReservationFactory::new();
    }
}
