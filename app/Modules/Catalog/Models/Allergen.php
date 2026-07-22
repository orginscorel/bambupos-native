<?php

namespace App\Modules\Catalog\Models;

use App\Modules\Tenancy\TenantContext;
use App\Modules\Tenancy\TenantIsolationException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Alerjen / diyet etiketi sözlüğü (DATA_MIGRATION_PLAN §4.6):
 *  - tenant_id NULL  → küresel satır (14 AB alerjeni + diyet etiketleri; kiracı DÜZENLEYEMEZ)
 *  - tenant_id dolu  → kiracının kendi eklediği satır
 *
 * BelongsToTenant KULLANILMAZ: fail-closed scope küresel satırları gizlerdi.
 * Bunun yerine "küresel VEYA kendi kiracısı" scope'u uygulanır; kiracıya ait
 * satır yazımı yine bağlamdan zorlanır (mass-assignment ile tenant_id yazılamaz).
 */
class Allergen extends Model
{
    public const KINDS = ['allergen', 'diet'];

    protected $fillable = [
        'kind',
        'code',
        'name',
        'description',
        'icon',
        'color',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'sort_order' => 'integer',
        ];
    }

    protected static function booted(): void
    {
        static::addGlobalScope('tenantOrGlobal', function (Builder $builder): void {
            /** @var TenantContext $context */
            $context = app(TenantContext::class);

            if ($context->bypassed()) {
                return;
            }

            $tenantId = $context->tenantId();

            $builder->where(function (Builder $q) use ($tenantId): void {
                $q->whereNull('allergens.tenant_id');

                if ($tenantId !== null) {
                    $q->orWhere('allergens.tenant_id', $tenantId);
                }
            });
        });

        static::creating(function (self $model): void {
            /** @var TenantContext $context */
            $context = app(TenantContext::class);

            if ($context->bypassed()) {
                return; // seed: küresel satır (tenant_id NULL) yazabilir
            }

            $tenantId = $context->tenantId();

            if ($tenantId === null) {
                throw new TenantIsolationException('Kiracı bağlamı yokken alerjen kaydı oluşturulamaz.');
            }

            // İstek akışında üretilen satır DAİMA kiracıya aittir.
            $model->tenant_id = $tenantId;
        });
    }

    /** Küresel (salt-okunur sözlük) satırı mı? */
    public function isGlobal(): bool
    {
        return $this->tenant_id === null;
    }

    public function products(): BelongsToMany
    {
        return $this->belongsToMany(Product::class);
    }
}
