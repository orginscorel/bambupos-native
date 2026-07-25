<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Denormalize anlık stok (depo × kalem). TEK doğruluk kaynağı DEFTERDİR
 * (inv_movements); bu tablo yalnız StockLedger tarafından, hareketle AYNI
 * transaction içinde güncellenir. Elle yazılmaz.
 */
class StockLevel extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_stock_levels';

    protected $fillable = [];

    protected function casts(): array
    {
        return ['qty_milli' => 'integer'];
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }
}
