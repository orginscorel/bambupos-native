<?php

namespace App\Modules\Receivables\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Cari defter satırı — DEĞİŞMEZ (CashMovement ile aynı desen). `updated_at`
 * yok (immutable ledger); yalnız ReceivableService içinden yazılır.
 *
 * amount_minor İŞARETLİDİR: borç transferi/düzeltme(+), tahsilat(-).
 */
class ReceivableTransaction extends Model
{
    use BelongsToTenant;

    public $timestamps = false;

    protected $fillable = [
        'receivable_id',
        'order_id',
        'type',
        'amount_minor',
        'method',
        'note',
        'balance_after_minor',
        'performed_by_id',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'amount_minor' => 'integer',
            'balance_after_minor' => 'integer',
            'created_at' => 'datetime',
        ];
    }

    public function receivable(): BelongsTo
    {
        return $this->belongsTo(Receivable::class);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function performedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'performed_by_id');
    }
}
