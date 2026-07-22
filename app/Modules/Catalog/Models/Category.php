<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Hiyerarşik, sıralı menü kategorisi (tenant-scoped).
 * slug kiracı içinde benzersizdir (UNIQUE(tenant_id, slug)).
 */
class Category extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'name',
        'slug',
        'description',
        'parent_id',
        'icon',
        'color',
        'image_path',
        'available_from',
        'available_until',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_id')->orderBy('sort_order');
    }

    public function products(): HasMany
    {
        return $this->hasMany(Product::class)->orderBy('sort_order');
    }

    public function menus(): BelongsToMany
    {
        return $this->belongsToMany(Menu::class);
    }
}
