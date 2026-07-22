<?php

namespace App\Modules\Tenancy;

use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Support\Facades\Auth;

/**
 * Kiracı bağlamı (istek başına singleton).
 *
 * Çözümleme sırası:
 *  1. Açıkça set edilen kiracı (public QR akışı, testler, seed)
 *  2. Oturumdaki kullanıcının tenant_id'si
 *  3. Hiçbiri yoksa NULL → TenantScope "fail closed" davranır (hiç satır dönmez).
 *
 * ADR-004: kiracı kimliği ASLA istek parametresinden alınmaz.
 */
class TenantContext
{
    private ?int $tenantId = null;

    private bool $explicitlySet = false;

    /** Sistem işleri (seed, cron, konsol) için bilinçli kapsam dışı çalışma. */
    private bool $bypassed = false;

    public function setTenant(Tenant|int|null $tenant): void
    {
        $this->tenantId = $tenant instanceof Tenant ? (int) $tenant->getKey() : ($tenant === null ? null : (int) $tenant);
        $this->explicitlySet = true;
    }

    public function forget(): void
    {
        $this->tenantId = null;
        $this->explicitlySet = false;
        $this->bypassed = false;
    }

    public function tenantId(): ?int
    {
        if ($this->explicitlySet) {
            return $this->tenantId;
        }

        $user = Auth::user();

        return $user?->tenant_id !== null ? (int) $user->tenant_id : null;
    }

    public function bypassed(): bool
    {
        return $this->bypassed;
    }

    /**
     * Kapsamsız çalıştır (yalnız sistem kodu: seed, bakım komutları).
     * Uygulama istek akışında KULLANILMAZ.
     */
    public function runWithoutTenancy(callable $callback): mixed
    {
        $previous = $this->bypassed;
        $this->bypassed = true;

        try {
            return $callback();
        } finally {
            $this->bypassed = $previous;
        }
    }
}
