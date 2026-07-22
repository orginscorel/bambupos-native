<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\ProductFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Faz-1 iskeleti: kiracılık omurgası + ADR-007 para alanları.
 * Catalog fazı alan ekleyecek; tenant kolonlarına dokunmayacak.
 */
class Product extends Model
{
    /** @use HasFactory<ProductFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'name',
        'sku',
        'price_minor',
        'currency',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    protected static function newFactory(): Factory
    {
        return ProductFactory::new();
    }
}
