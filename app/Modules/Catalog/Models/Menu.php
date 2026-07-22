<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Menü planı (kahvaltı/öğle/akşam…): hangi kategoriler, hangi günler,
 * hangi saat aralığı ve hangi kanallarda görünür.
 */
class Menu extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = [
        'name',
        'description',
        'branch_id',
        'days',
        'start_time',
        'end_time',
        'channels',
        'sort_order',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'days' => 'array',
            'channels' => 'array',
            'sort_order' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function categories(): BelongsToMany
    {
        return $this->belongsToMany(Category::class)
            ->withPivot('sort_order')
            ->orderByPivot('sort_order');
    }
}
