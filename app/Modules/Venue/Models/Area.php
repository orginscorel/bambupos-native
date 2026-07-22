<?php

namespace App\Modules\Venue\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tables\Models\Table;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use App\Modules\Venue\Enums\AreaType;
use Database\Factories\AreaFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Salon/alan (şube → kat → SALON/ALAN → masa). */
class Area extends Model
{
    /** @use HasFactory<AreaFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $table = 'venue_areas';

    protected $fillable = [
        'name',
        'type',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'type' => AreaType::class,
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function floor(): BelongsTo
    {
        return $this->belongsTo(Floor::class, 'floor_id');
    }

    public function tables(): HasMany
    {
        return $this->hasMany(Table::class, 'area_id');
    }

    protected static function newFactory(): Factory
    {
        return AreaFactory::new();
    }
}
