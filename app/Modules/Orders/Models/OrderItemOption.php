<?php

namespace App\Modules\Orders\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Kalem seçeneği — grup/seçenek adı ve fiyatı satış anı snapshot'ıdır
 * (prompt §25); option_id yalnız referans (nullable).
 */
class OrderItemOption extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'option_id',
        'group_name',
        'option_name',
        'price_minor',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
        ];
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(OrderItem::class, 'order_item_id');
    }
}
