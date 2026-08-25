<?php

declare(strict_types=1);

namespace App\Modules\Commission\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * Prim şeması (commission_schemes). Kiracıya ait (BelongsToTenant); yönetici
 * tanımlar. Bir şema ya belirli bir pozisyona (position) ya da herkese
 * (position = null) uygulanır. Prim tabanı `basis` ile seçilir:
 * percent_sales | per_order | target_bonus.
 *
 * tenant_id BİLİNÇLİ olarak fillable DEĞİL (BelongsToTenant; bağlamdan atanır).
 */
class CommissionScheme extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'name',
        'basis',
        'rate_bps',
        'per_order_minor',
        'target_minor',
        'bonus_minor',
        'position',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'rate_bps' => 'integer',
            'per_order_minor' => 'integer',
            'target_minor' => 'integer',
            'bonus_minor' => 'integer',
            'is_active' => 'boolean',
        ];
    }
}
