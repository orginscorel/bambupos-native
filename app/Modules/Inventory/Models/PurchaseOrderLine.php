<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Satın alma satırı. unit_price_minor = kuruş / ANA birim. */
class PurchaseOrderLine extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_purchase_lines';

    protected $fillable = ['item_id', 'qty_milli', 'unit_price_minor', 'tax_rate'];

    protected function casts(): array
    {
        return [
            'qty_milli' => 'integer',
            'received_qty_milli' => 'integer',
            'returned_qty_milli' => 'integer',
            'unit_price_minor' => 'integer',
            'tax_rate' => 'decimal:2',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class, 'purchase_order_id');
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }
}
