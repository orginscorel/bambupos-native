<?php

namespace App\Modules\Tenancy\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\BranchFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * Şube/tesis. Her zaman bir tenant'a bağlıdır (ADR-004).
 */
class Branch extends Model
{
    /** @use HasFactory<BranchFactory> */
    use BelongsToTenant, HasFactory;

    protected $fillable = [
        'name',
        'code',
        'address',
        'phone',
        'showcase',
        'timezone',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'showcase' => 'array',
        ];
    }

    protected static function newFactory(): Factory
    {
        return BranchFactory::new();
    }
}
