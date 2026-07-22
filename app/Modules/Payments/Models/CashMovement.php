<?php

namespace App\Modules\Payments\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Payments\Enums\CashMovementType;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Kasa hareketi — DEĞİŞMEZ defter kaydı (prompt §16).
 *
 * Yazıldıktan sonra yalnız `reversed_by_id` (ters kayıt bağlantısı)
 * güncellenebilir; başka her alan değişikliği istisna fırlatır.
 * Silme YASAK. Düzeltme = CashSessionService::reverse (ters kayıt).
 */
class CashMovement extends Model
{
    use BelongsToTenant;

    public const UPDATED_AT = null; // defter kaydı: yalnız created_at

    protected $fillable = ['type', 'direction', 'amount_minor', 'reason'];

    protected function casts(): array
    {
        return ['amount_minor' => 'integer', 'created_at' => 'datetime'];
    }

    protected static function booted(): void
    {
        static::updating(function (CashMovement $movement): void {
            $dirty = array_keys($movement->getDirty());
            $forbidden = array_diff($dirty, ['reversed_by_id']);

            if ($forbidden !== []) {
                throw new \LogicException(
                    'Kasa hareketi geriye dönük değiştirilemez ('.implode(', ', $forbidden).'); ters kayıt kullanın.'
                );
            }
        });

        static::deleting(function (): void {
            throw new \LogicException('Kasa hareketi silinemez; ters kayıt kullanın.');
        });
    }

    public function typeEnum(): CashMovementType
    {
        return CashMovementType::tryFrom((string) $this->type) ?? CashMovementType::CashIn;
    }

    public function session(): BelongsTo
    {
        return $this->belongsTo(CashSession::class, 'cash_session_id');
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function reverses(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reverses_id');
    }

    public function reversedBy(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reversed_by_id');
    }
}
