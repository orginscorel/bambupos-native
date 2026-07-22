<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Ürün varyantı: boyut/porsiyon (Küçük–Orta–Büyük vb.), kendi fiyatıyla. */
class ProductVariant extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'product_id',
        'name',
        'price_minor',
        'is_default',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
            'is_default' => 'boolean',
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
