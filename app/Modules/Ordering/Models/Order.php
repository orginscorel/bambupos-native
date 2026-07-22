<?php

namespace App\Modules\Ordering\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\OrderFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Faz-1 iskeleti. total_minor: ADR-007 kuruş-integer.
 */
class Order extends Model
{
    /** @use HasFactory<OrderFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'status',
        'total_minor',
        'currency',
    ];

    protected function casts(): array
    {
        return [
            'total_minor' => 'integer',
        ];
    }

    protected static function newFactory(): Factory
    {
        return OrderFactory::new();
    }
}
