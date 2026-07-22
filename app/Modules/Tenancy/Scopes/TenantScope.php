<?php

namespace App\Modules\Tenancy\Scopes;

use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Katman 1 (ADR-004): global scope.
 * Kiracı bağlamı yoksa hiçbir satır dönmez (fail closed) —
 * "filtre unutuldu" hatası veri sızdırmaz, boş sonuç verir.
 */
class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $context = app(TenantContext::class);

        if ($context->bypassed()) {
            return;
        }

        $tenantId = $context->tenantId();

        if ($tenantId === null) {
            $builder->whereRaw('1 = 0');

            return;
        }

        $builder->where($model->qualifyColumn('tenant_id'), $tenantId);
    }
}
