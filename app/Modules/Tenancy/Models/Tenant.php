<?php

namespace App\Modules\Tenancy\Models;

use Database\Factories\TenantFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Kiracı = sözleşme/müşteri (ör. bir belediye). ADR-004 hiyerarşi kökü.
 * Bu model kiracı-scoped DEĞİLDİR (kendisi kök); yönetimi yalnız
 * platform/konsol tarafında yapılır, panel rotalarına bağlanmaz.
 */
class Tenant extends Model
{
    /** @use HasFactory<TenantFactory> */
    use HasFactory;

    protected $fillable = [
        'name',
        'slug',
        'domain',
        'status',
        'settings',
    ];

    protected function casts(): array
    {
        return [
            'settings' => 'array',
        ];
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    protected static function newFactory(): Factory
    {
        return TenantFactory::new();
    }
}
