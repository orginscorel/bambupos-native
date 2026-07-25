<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use LogicException;

/**
 * DEĞİŞMEZ hareket defteri satırı (§17.4).
 *
 * KURAL: Defter satırı ASLA güncellenmez ve silinmez — yanlış kayıt ters
 * kayıtla (karşı işaretli yeni satır) düzeltilir. updating/deleting model
 * olayları istisna fırlatır; toplu Query Builder yazımı da yasaktır
 * (kod incelemesi + test LedgerImmutabilityTest bunu korur).
 *
 * qty_milli İMZALIDIR: + giriş, − çıkış (ana birim ×1000).
 */
class StockMovement extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_movements';

    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'qty_milli' => 'integer',
            'unit_cost_minor' => 'integer',
            'total_cost_minor' => 'integer',
            'expires_at' => 'date',
            'approved_at' => 'datetime',
            'occurred_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::updating(function (): never {
            throw new LogicException('Stok hareket defteri değişmezdir: satır güncellenemez; ters kayıt kullanın.');
        });

        static::deleting(function (): never {
            throw new LogicException('Stok hareket defteri değişmezdir: satır silinemez; ters kayıt kullanın.');
        });
    }

    public function typeEnum(): MovementType
    {
        return MovementType::tryFrom((string) $this->type) ?? MovementType::ManualAdjust;
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }
}
