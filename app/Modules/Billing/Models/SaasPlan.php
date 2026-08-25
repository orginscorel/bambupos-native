<?php

namespace App\Modules\Billing\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * SaaS abonelik paketi kataloğu (platform geliri). config/pricing_saas.php
 * ile hizalı; varsayılan satırlar migration'da tohumlanır. Kiracı-scoped
 * DEĞİLDİR (Tenant modeliyle aynı mantık — yalnız platform/süper-admin
 * yönetir).
 */
class SaasPlan extends Model
{
    protected $fillable = [
        'key',
        'name',
        'price_minor',
        'currency',
        'interval',
        'features',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'price_minor' => 'integer',
            'features' => 'array',
            'is_active' => 'boolean',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(SaasSubscription::class, 'plan_key', 'key');
    }
}
