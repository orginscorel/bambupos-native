<?php

namespace App\Modules\Billing\Models;

use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * İşletme (tenant) başına SaaS abonelik durumu (platform geliri).
 * Kiracı-scoped DEĞİLDİR — Tenant modeliyle aynı mantık (ADR-004 kapsamı
 * dışında; yönetimi yalnız platform/süper-admin tarafında yapılır).
 */
class SaasSubscription extends Model
{
    public const STATUS_TRIAL = 'trial';

    public const STATUS_ACTIVE = 'active';

    public const STATUS_PAST_DUE = 'past_due';

    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'tenant_id',
        'plan_key',
        'status',
        'current_period_end',
        'cancel_at_period_end',
    ];

    protected function casts(): array
    {
        return [
            'current_period_end' => 'date',
            'cancel_at_period_end' => 'boolean',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(SaasPlan::class, 'plan_key', 'key');
    }

    public function invoices(): HasMany
    {
        return $this->hasMany(SaasInvoice::class, 'subscription_id');
    }

    public function isActive(): bool
    {
        return in_array($this->status, [self::STATUS_TRIAL, self::STATUS_ACTIVE], true);
    }
}
