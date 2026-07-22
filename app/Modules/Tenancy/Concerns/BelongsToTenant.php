<?php

namespace App\Modules\Tenancy\Concerns;

use App\Modules\Tenancy\Models\Tenant;
use App\Modules\Tenancy\Scopes\TenantScope;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Kiracıya ait tüm modeller bu trait'i kullanır (ADR-004 katman 1).
 *
 * - Sorgular otomatik tenant_id ile süzülür (TenantScope, fail closed).
 * - creating: tenant_id bağlamdan otomatik atanır; bağlamla çelişen
 *   veya bağlamsız+tenant'sız kayıt yazımı istisna fırlatır.
 * - tenant_id hiçbir modelde fillable DEĞİLDİR; istekten gelen tenant_id
 *   mass-assignment ile asla yazılamaz.
 */
trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);

        static::creating(function ($model): void {
            /** @var TenantContext $context */
            $context = app(TenantContext::class);

            if ($context->bypassed()) {
                if ($model->tenant_id === null) {
                    throw new TenantIsolationException(sprintf(
                        'Kapsam dışı modda %s yazılırken tenant_id açıkça verilmelidir.', static::class
                    ));
                }

                return;
            }

            $contextTenantId = $context->tenantId();

            if ($model->tenant_id === null) {
                if ($contextTenantId === null) {
                    throw new TenantIsolationException(sprintf(
                        'Kiracı bağlamı yokken %s oluşturulamaz.', static::class
                    ));
                }

                $model->tenant_id = $contextTenantId;

                return;
            }

            if ($contextTenantId !== null && (int) $model->tenant_id !== $contextTenantId) {
                throw new TenantIsolationException(sprintf(
                    '%s kaydı bağlamdaki kiracıdan farklı bir tenant_id ile oluşturulmaya çalışıldı.', static::class
                ));
            }
        });
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /** Yalnız sistem kodu için: kapsamı bilinçli kaldır. */
    public static function withoutTenancy(): Builder
    {
        return static::query()->withoutGlobalScope(TenantScope::class);
    }
}
