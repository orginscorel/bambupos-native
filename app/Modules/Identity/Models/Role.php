<?php

namespace App\Modules\Identity\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Database\Factories\RoleFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Rol: kiracıya aittir, sabit kodlanmaz — her işletme kendi rolünü tanımlar.
 * is_system: seed ile gelen korunan roller (ör. Sahip) — silinemez,
 * izin seti sistem tarafından yönetilir.
 */
class Role extends Model
{
    /** @use HasFactory<RoleFactory> */
    use Auditable, BelongsToTenant, HasFactory;

    protected $fillable = [
        'name',
        'slug',
        'description',
    ];

    protected function casts(): array
    {
        return [
            'is_system' => 'boolean',
        ];
    }

    public function permissions(): BelongsToMany
    {
        return $this->belongsToMany(Permission::class, 'permission_role');
    }

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'role_user')->withTimestamps();
    }

    protected static function newFactory(): Factory
    {
        return RoleFactory::new();
    }
}
