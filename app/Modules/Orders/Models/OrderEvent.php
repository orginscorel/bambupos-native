<?php

namespace App\Modules\Orders\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Sipariş olay günlüğü: durum geçişleri + adisyon işlemleri (taşı/birleştir/
 * böl/ikram/indirim/iptal…). İkram/indirim/iptal ayrıca audit_logs'a düşer
 * (prompt §12.3); burası operasyonel zaman çizelgesidir.
 */
class OrderEvent extends Model
{
    use BelongsToTenant;

    public const UPDATED_AT = null;

    protected $fillable = [
        'order_item_id',
        'type',
        'from_status',
        'to_status',
        'payload',
    ];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'created_at' => 'datetime',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
