<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\Storage;

/** Ürün görseli; dosya `public` diskinde tenant-izolasyonlu yolda durur. */
class ProductImage extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'product_id',
        'path',
        'original_name',
        'mime',
        'size',
        'is_primary',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'size' => 'integer',
            'is_primary' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    protected $appends = ['url'];

    public function getUrlAttribute(): string
    {
        return Storage::disk('public')->url($this->path);
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
