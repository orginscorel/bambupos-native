<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Stok sayımı (§17 sayım ekranı). KÖR SAYIM: beklenen miktar, sayım
 * GÖNDERİLENE kadar sayan kişiye gösterilmez; beklenen değer gönderim
 * anında snapshot'lanır, fark oradan hesaplanır. Onay `stock.adjust`
 * ister ve farkları count_adjust hareketleriyle deftere işler.
 */
class StockCount extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_counts';

    public const STATUS_DRAFT = 'draft';
    public const STATUS_SUBMITTED = 'submitted';
    public const STATUS_APPROVED = 'approved';
    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = ['warehouse_id', 'is_blind', 'note'];

    protected function casts(): array
    {
        return [
            'is_blind' => 'boolean',
            'submitted_at' => 'datetime',
            'approved_at' => 'datetime',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(StockCountLine::class, 'count_id')->orderBy('id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }
}
