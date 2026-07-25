<?php

namespace App\Modules\Inventory\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Inventory\Enums\WarehouseType;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Depo (§17.1): ana/şube/mutfak/bar/soğuk/sarf/özel. */
class Warehouse extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'inv_warehouses';

    protected $fillable = ['name', 'code', 'type', 'branch_id', 'is_default', 'is_active'];

    protected function casts(): array
    {
        return ['is_default' => 'boolean', 'is_active' => 'boolean'];
    }

    public function typeEnum(): WarehouseType
    {
        return WarehouseType::tryFrom((string) $this->type) ?? WarehouseType::Custom;
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function levels(): HasMany
    {
        return $this->hasMany(StockLevel::class, 'warehouse_id');
    }

    /**
     * Şube için varsayılan tüketim deposu: şubenin is_default deposu →
     * şubenin herhangi bir aktif deposu → kiracının varsayılanı → ilk aktif.
     * (Kiracı bağlamından bağımsız çalışır; sistem kodu da çağırır.)
     */
    public static function defaultFor(int $tenantId, ?int $branchId): ?self
    {
        $base = fn () => static::withoutTenancy()
            ->where('tenant_id', $tenantId)->where('is_active', true);

        if ($branchId !== null) {
            $branchDefault = $base()->where('branch_id', $branchId)->orderByDesc('is_default')->orderBy('id')->first();

            if ($branchDefault !== null) {
                return $branchDefault;
            }
        }

        return $base()->orderByDesc('is_default')->orderBy('id')->first();
    }
}
