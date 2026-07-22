<?php

namespace App\Modules\Kds\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Komi "teslim aldım" işareti. Orders'ın kalem durum makinesine ara durum
 * eklemeden (ready→served arası) komi akışını taşır; KDS modülünün KENDİ
 * verisidir. "Masaya götürdüm" = OrderService::setItemStatus(served).
 */
class ItemPickup extends Model
{
    use BelongsToTenant;

    protected $table = 'kds_item_pickups';

    public const UPDATED_AT = null;

    protected $fillable = ['order_item_id', 'user_id'];

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
