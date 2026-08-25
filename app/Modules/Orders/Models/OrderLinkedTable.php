<?php

namespace App\Modules\Orders\Models;

use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Adisyona SONRADAN bağlanmış masa (grup birleştirmesi).
 * Adisyonun kendi masası burada tutulmaz — bkz. migration açıklaması.
 */
class OrderLinkedTable extends Model
{
    use BelongsToTenant;

    public $timestamps = false;

    protected $fillable = ['order_id', 'table_id', 'created_at'];

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(Table::class);
    }
}
