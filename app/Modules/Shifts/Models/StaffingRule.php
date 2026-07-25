<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Minimum personel kuralı: şube (+isteğe bağlı gün/pozisyon) → alt sınır. */
class StaffingRule extends Model
{
    use Auditable, BelongsToTenant;

    protected $table = 'shift_staffing_rules';

    protected $fillable = ['branch_id', 'weekday', 'position', 'min_count'];

    protected function casts(): array
    {
        return [
            'weekday' => 'integer',
            'min_count' => 'integer',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
