<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Sayım satırı. expected/diff gönderim anında doldurulur (kör sayım). */
class StockCountLine extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_count_lines';

    protected $fillable = ['item_id', 'counted_qty_milli'];

    protected function casts(): array
    {
        return [
            'counted_qty_milli' => 'integer',
            'expected_qty_milli' => 'integer',
            'diff_qty_milli' => 'integer',
        ];
    }

    public function count(): BelongsTo
    {
        return $this->belongsTo(StockCount::class, 'count_id');
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }
}
