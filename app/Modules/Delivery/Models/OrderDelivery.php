<?php

declare(strict_types=1);

namespace App\Modules\Delivery\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Teslimat kaydı (order_deliveries). Her paket siparişe (Order
 * service_type=package) eşlik eder. Kiracıya ait (BelongsToTenant) + şube
 * kapsamlı. Yönetici kuryeye atar (courier_id), kurye durumunu ilerletir
 * (pending → assigned → on_the_way → delivered | failed).
 *
 * tenant_id BİLİNÇLİ olarak fillable DEĞİL (BelongsToTenant; bağlamdan atanır).
 */
class OrderDelivery extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'order_id',
        'branch_id',
        'address',
        'note',
        'courier_id',
        'status',
        'fee_minor',
        'assigned_at',
        'delivered_at',
    ];

    protected function casts(): array
    {
        return [
            'fee_minor' => 'integer',
            'assigned_at' => 'datetime',
            'delivered_at' => 'datetime',
        ];
    }

    /* ---------------- İlişkiler ---------------- */

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    /** Atanan kurye (personel). */
    public function courier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'courier_id');
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    /* ---------------- Sunum ---------------- */

    /** İnsan-okur durum etiketi (TR). */
    public function statusLabel(): string
    {
        return match ($this->status) {
            'pending' => 'Bekliyor',
            'assigned' => 'Atandı',
            'on_the_way' => 'Yolda',
            'delivered' => 'Teslim edildi',
            'failed' => 'Başarısız',
            default => (string) $this->status,
        };
    }
}
