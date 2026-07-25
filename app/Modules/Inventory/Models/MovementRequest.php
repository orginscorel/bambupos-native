<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Manuel hareket İSTEĞİ (§17.4 "onay"): panelden girilen manuel hareket
 * önce buraya düşer; `stock.adjust` yetkilisi ONAYLAYINCA gerçek deftere
 * (inv_movements) yazılır. Defter böylece saf-değişmez kalır.
 */
class MovementRequest extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_movement_requests';

    public const STATUS_PENDING = 'pending';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_REJECTED = 'rejected';

    protected $fillable = [
        'warehouse_id', 'item_id', 'type', 'qty_milli',
        'unit_cost_minor', 'lot_no', 'expires_at', 'description',
    ];

    protected function casts(): array
    {
        return [
            'qty_milli' => 'integer',
            'unit_cost_minor' => 'integer',
            'expires_at' => 'date',
            'decided_at' => 'datetime',
        ];
    }

    public function typeEnum(): MovementType
    {
        return MovementType::tryFrom((string) $this->type) ?? MovementType::ManualAdjust;
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(StockItem::class, 'item_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }

    public function requestedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by_id');
    }
}
