<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductVariant;
use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Reçete başlığı (§17.3). Hedef: ürün(+varyant) YA DA yarı mamul stok
 * kalemi (item_id). branch_id doluysa şubeye özel reçetedir.
 *
 * VERSİYONLAMA: değişiklik = YENİ satır (version+1); eskisi is_active=false
 * olarak tarihçede kalır. Aynı hedef için tek aktif sürüm bulunur.
 */
class Recipe extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_recipes';

    protected $fillable = [
        'product_id', 'variant_id', 'item_id', 'branch_id',
        'yield_qty_milli', 'waste_percent', 'note',
    ];

    protected function casts(): array
    {
        return [
            'version' => 'integer',
            'yield_qty_milli' => 'integer',
            'waste_percent' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(RecipeLine::class, 'recipe_id')->orderBy('sort_order')->orderBy('id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function variant(): BelongsTo
    {
        return $this->belongsTo(ProductVariant::class, 'variant_id');
    }

    public function targetItem(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }
}
