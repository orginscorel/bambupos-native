<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Stok kartı (§17.2). Miktarlar ana birim ×1000 tamsayı (`*_qty_milli`),
 * maliyetler kuruş / ana birim (ADR-007).
 *
 * ÖNEMLİ: `avg_cost_minor` yalnız StockLedger tarafından güncellenir
 * (hareketli ortalama); ekrandan elle değiştirilmez.
 */
class StockItem extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_items';

    protected $fillable = [
        'name', 'code', 'barcode', 'category_id',
        'base_unit', 'sub_unit', 'sub_unit_factor',
        'min_qty_milli', 'critical_qty_milli', 'max_qty_milli',
        'default_supplier_id', 'track_expiry', 'track_lot',
        'shelf_location', 'tax_rate', 'is_semi_finished', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'sub_unit_factor' => 'integer',
            'min_qty_milli' => 'integer',
            'critical_qty_milli' => 'integer',
            'max_qty_milli' => 'integer',
            'avg_cost_minor' => 'integer',
            'last_cost_minor' => 'integer',
            'last_purchase_at' => 'datetime',
            'track_expiry' => 'boolean',
            'track_lot' => 'boolean',
            'tax_rate' => 'decimal:2',
            'is_semi_finished' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ItemCategory::class, 'category_id');
    }

    public function defaultSupplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class, 'default_supplier_id');
    }

    public function levels(): HasMany
    {
        return $this->hasMany(StockLevel::class, 'item_id');
    }

    public function movements(): HasMany
    {
        return $this->hasMany(StockMovement::class, 'item_id');
    }

    /** Tüm depolardaki toplam stok (milli). */
    public function totalOnHandMilli(): int
    {
        return (int) $this->levels()->sum('qty_milli');
    }
}
