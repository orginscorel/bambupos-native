<?php

namespace App\Modules\Billing\Models;

use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * SaaS abonelik faturası (platform geliri). `payments` tablosuyla
 * KARIŞTIRILMAMALI — bu POS/kasa tahsilatı değildir. Gerçek ödeme
 * sağlayıcı (iyzico/PayTR) entegrasyonu YOK; yalnız veri modeli
 * (bkz. App\Modules\Billing\Services\BillingService).
 */
class SaasInvoice extends Model
{
    public const STATUS_DRAFT = 'draft';

    public const STATUS_UNPAID = 'unpaid';

    public const STATUS_PAID = 'paid';

    public const STATUS_VOID = 'void';

    protected $fillable = [
        'tenant_id',
        'subscription_id',
        'number',
        'amount_minor',
        'currency',
        'status',
        'issued_at',
        'due_at',
        'paid_at',
        'meta',
    ];

    protected function casts(): array
    {
        return [
            'amount_minor' => 'integer',
            'issued_at' => 'datetime',
            'due_at' => 'datetime',
            'paid_at' => 'datetime',
            'meta' => 'array',
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function subscription(): BelongsTo
    {
        return $this->belongsTo(SaasSubscription::class, 'subscription_id');
    }

    public function isPaid(): bool
    {
        return $this->status === self::STATUS_PAID;
    }
}
