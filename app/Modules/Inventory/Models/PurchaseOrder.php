<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Inventory\Enums\PurchaseStatus;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Satın alma belgesi (§17.6): talep → teklif → sipariş → mal kabul → fatura. */
class PurchaseOrder extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_purchase_orders';

    public const PAYMENT_UNPAID = 'unpaid';
    public const PAYMENT_PARTIAL = 'partial';
    public const PAYMENT_PAID = 'paid';

    protected $fillable = ['supplier_id', 'warehouse_id', 'branch_id', 'expected_at', 'note'];

    protected function casts(): array
    {
        return [
            'invoice_total_minor' => 'integer',
            'paid_minor' => 'integer',
            'invoiced_at' => 'datetime',
            'due_date' => 'date',
            'expected_at' => 'date',
            'ordered_at' => 'datetime',
        ];
    }

    public function statusEnum(): PurchaseStatus
    {
        return PurchaseStatus::tryFrom((string) $this->status) ?? PurchaseStatus::Draft;
    }

    public function lines(): HasMany
    {
        return $this->hasMany(PurchaseOrderLine::class, 'purchase_order_id')->orderBy('id');
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class, 'supplier_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }
}
