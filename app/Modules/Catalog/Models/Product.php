<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\ProductFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Katalog ürünü. Kiracılık omurgası Faz-1'den; ürün alanları Faz-2 (Katalog).
 * Para alanları kuruş-integer `*_minor` (ADR-007); tax_rate orandır.
 */
class Product extends Model
{
    /** @use HasFactory<ProductFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    /** Satış kanalı anahtarları (channels JSON + menü kanal kuralları). */
    public const CHANNELS = ['qr', 'kiosk', 'package', 'pos'];

    protected $fillable = [
        'name',
        'description',
        'sku',
        'barcode',
        'category_id',
        'price_minor',
        'cost_minor',
        'package_price_minor',
        'kiosk_price_minor',
        'qr_price_minor',
        'discounted_price_minor',
        'currency',
        'tax_rate',
        'portion',
        'unit',
        'prep_minutes',
        'calories',
        'protein',
        'carbs',
        'fat',
        'spiciness',
        'is_new',
        'is_chef_pick',
        'is_bestseller',
        'is_active',
        'is_available',
        'channels',
        'available_from',
        'available_until',
        'station',
        'track_stock',
        'stock_quantity',
        'min_order_qty',
        'max_order_qty',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
            'cost_minor' => 'integer',
            'package_price_minor' => 'integer',
            'kiosk_price_minor' => 'integer',
            'qr_price_minor' => 'integer',
            'discounted_price_minor' => 'integer',
            'tax_rate' => 'decimal:2',
            'prep_minutes' => 'integer',
            'calories' => 'integer',
            'protein' => 'decimal:2',
            'carbs' => 'decimal:2',
            'fat' => 'decimal:2',
            'spiciness' => 'integer',
            'is_new' => 'boolean',
            'is_chef_pick' => 'boolean',
            'is_bestseller' => 'boolean',
            'is_active' => 'boolean',
            'is_available' => 'boolean',
            'channels' => 'array',
            'track_stock' => 'boolean',
            'stock_quantity' => 'integer',
            'min_order_qty' => 'integer',
            'max_order_qty' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    public function variants(): HasMany
    {
        return $this->hasMany(ProductVariant::class)->orderBy('sort_order');
    }

    public function optionGroups(): BelongsToMany
    {
        return $this->belongsToMany(OptionGroup::class)
            ->withPivot('sort_order')
            ->orderByPivot('sort_order');
    }

    public function allergens(): BelongsToMany
    {
        return $this->belongsToMany(Allergen::class);
    }

    public function images(): HasMany
    {
        return $this->hasMany(ProductImage::class)->orderByDesc('is_primary')->orderBy('sort_order');
    }

    protected static function newFactory(): Factory
    {
        return ProductFactory::new();
    }
}
