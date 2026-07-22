<?php

namespace App\Modules\Venue\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Database\Factories\FloorFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Kat (şube → KAT → salon/alan → masa). */
class Floor extends Model
{
    /** @use HasFactory<FloorFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $table = 'venue_floors';

    protected $fillable = [
        'name',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'sort_order' => 'integer',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function areas(): HasMany
    {
        return $this->hasMany(Area::class, 'floor_id');
    }

    protected static function newFactory(): Factory
    {
        return FloorFactory::new();
    }
}
