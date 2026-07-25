<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Tedarikçi fiyat geçmişi — mal kabulünde otomatik yazılır (§17.6). */
class SupplierPrice extends Model
{
    use BelongsToTenant;

    protected $fillable = [];

    protected $table = 'inv_supplier_prices';

    protected function casts(): array
    {
        return ['unit_price_minor' => 'integer', 'recorded_at' => 'datetime'];
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }
}
