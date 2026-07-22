<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Seçenek grubu: zorunlu/opsiyonel, tek/çoklu seçim, min/max adet,
 * ücretsiz adet (free_limit) kuralları. Ürünlere pivot ile bağlanır.
 */
class OptionGroup extends Model
{
    use Auditable, BelongsToTenant;

    public const SELECTION_TYPES = ['single', 'multiple'];

    protected $fillable = [
        'name',
        'description',
        'selection_type',
        'is_required',
        'min_select',
        'max_select',
        'free_limit',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_required' => 'boolean',
            'min_select' => 'integer',
            'max_select' => 'integer',
            'free_limit' => 'integer',
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function options(): HasMany
    {
        return $this->hasMany(Option::class)->orderBy('sort_order');
    }

    public function products(): BelongsToMany
    {
        return $this->belongsToMany(Product::class)->withPivot('sort_order');
    }
}
