<?php

namespace App\Modules\Settings\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Kiracı bazlı özellik (feature-flag) satırı — MODULE_MAP §9.
 *
 * Satır yoksa FeatureCatalog::default geçerlidir; bu tabloya YALNIZ opsiyonel
 * özellikler yazılır. Kiracı süzgeci açıkça FeatureService içinde uygulanır
 * (MailSetting gibi; global tenant scope KULLANMAZ — servis kapıdır).
 */
class TenantFeature extends Model
{
    protected $fillable = [
        'tenant_id',
        'feature',
        'enabled',
    ];

    protected function casts(): array
    {
        return [
            'enabled' => 'boolean',
        ];
    }
}
