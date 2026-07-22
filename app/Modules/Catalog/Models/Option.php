<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Grup içi tek seçenek; price_minor = ek ücret (0 = ücretsiz). */
class Option extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'option_group_id',
        'name',
        'price_minor',
        'is_default',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
            'is_default' => 'boolean',
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(OptionGroup::class, 'option_group_id');
    }
}
