<?php

namespace App\Modules\Orders\Models;

use App\Modules\Catalog\Models\Product;
use App\Modules\Catalog\Models\ProductVariant;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Adisyon kalemi. Ad/fiyat/KDV/seçenek fiyatı SATIŞ ANI SNAPSHOT'ıdır
 * (prompt §25): ürün sonradan değişse/silinse de bu satır DEĞİŞMEZ.
 * line_total/vat tek yerde hesaplanır (OrderService::computeLine).
 */
class OrderItem extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'product_id',
        'variant_id',
        'status',
        'qty',
        'name',
        'variant_name',
        'unit_price_minor',
        'options_price_minor',
        'tax_rate',
        'station',
        'discount_minor',
        'discount_reason',
        'is_comp',
        'comp_reason',
        'note',
    ];

    protected function casts(): array
    {
        return [
            'qty' => 'integer',
            'unit_price_minor' => 'integer',
            'options_price_minor' => 'integer',
            'tax_rate' => 'decimal:2',
            'discount_minor' => 'integer',
            'is_comp' => 'boolean',
            'line_total_minor' => 'integer',
            'vat_minor' => 'integer',
            'cancelled_at' => 'datetime',
        ];
    }

    public function statusEnum(): OrderItemStatus
    {
        return OrderItemStatus::tryFrom((string) $this->status) ?? OrderItemStatus::Placed;
    }

    public function isActive(): bool
    {
        return $this->statusEnum()->isActive();
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function options(): HasMany
    {
        return $this->hasMany(OrderItemOption::class)->orderBy('id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }

    public function variant(): BelongsTo
    {
        return $this->belongsTo(ProductVariant::class, 'variant_id');
    }

    public function addedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'added_by_id');
    }
}
