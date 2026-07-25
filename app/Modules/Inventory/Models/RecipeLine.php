<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Reçete satırı: 1 porsiyon (ya da 1 verim birimi) başına bileşen.
 * qty_milli ANA birim ×1000; unit_entry yalnız görüntü tercihi (base|sub).
 * item ham madde YA DA yarı mamul olabilir (yarı mamulün kendi stoğu düşer).
 */
class RecipeLine extends Model
{
    use BelongsToTenant;

    protected $table = 'inv_recipe_lines';

    protected $fillable = ['item_id', 'qty_milli', 'unit_entry', 'waste_percent', 'warehouse_id', 'sort_order'];

    protected function casts(): array
    {
        return [
            'qty_milli' => 'integer',
            'waste_percent' => 'decimal:2',
            'sort_order' => 'integer',
        ];
    }

    public function recipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class, 'recipe_id');
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }
}
