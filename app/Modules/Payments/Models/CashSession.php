<?php

namespace App\Modules\Payments\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Kasa oturumu: açılış → hareketler → sayım → kapanış (Z).
 * Kapanan oturum DONDURULUR (updating guard) — Z raporu `summary`
 * anlık görüntüsüyle sabitlenir; geriye dönük sessiz değişiklik yok.
 */
class CashSession extends Model
{
    use BelongsToTenant;

    protected $fillable = ['opening_float_minor', 'closing_note'];

    protected function casts(): array
    {
        return [
            'opening_float_minor' => 'integer',
            'expected_cash_minor' => 'integer',
            'counted_cash_minor' => 'integer',
            'difference_minor' => 'integer',
            'z_number' => 'integer',
            'summary' => 'array',
            'opened_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::updating(function (CashSession $session): void {
            // Kapanmış oturumda tek izinli değişiklik yoktur.
            if ($session->getOriginal('status') === 'closed') {
                throw new \LogicException('Kapanmış kasa oturumu değiştirilemez (Z raporu dondurulmuştur).');
            }
        });

        static::deleting(function (): void {
            throw new \LogicException('Kasa oturumu silinemez.');
        });
    }

    public function isOpen(): bool
    {
        return $this->status === 'open';
    }

    public function register(): BelongsTo
    {
        return $this->belongsTo(CashRegister::class, 'cash_register_id');
    }

    public function openedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'opened_by_id');
    }

    public function closedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'closed_by_id');
    }

    public function movements(): HasMany
    {
        return $this->hasMany(CashMovement::class)->orderBy('id');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    /**
     * Beklenen nakit = hareket defterinin net toplamı (tek kaynak:
     * cash_movements; ödeme/iade/void hareketleri sistemce yazılır).
     */
    public function expectedCashMinor(): int
    {
        $in = (int) $this->movements()->where('direction', 'in')->sum('amount_minor');
        $out = (int) $this->movements()->where('direction', 'out')->sum('amount_minor');

        return $in - $out;
    }
}
