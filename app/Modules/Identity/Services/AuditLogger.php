<?php

namespace App\Modules\Identity\Services;

use App\Modules\Identity\Models\AuditLog;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

/**
 * Denetim kaydı servisi. Hassas alanlar maskelenir; kayıt yazımı
 * ana işlemi asla düşürmez (best-effort ama exception yutulmaz — audit
 * yazılamıyorsa işlem de durmalıdır; kasıtlı tasarım).
 */
class AuditLogger
{
    /** Değeri asla saklanmayacak alanlar. */
    private const MASKED = [
        'password',
        'pin_hash',
        'remember_token',
        'two_factor_secret',
        'two_factor_recovery_codes',
        // Rezervasyon (Faz-9): sağlık verisi + public onay bağlantısı
        'allergy_note',
        'confirmation_token',
    ];

    public function __construct(private readonly TenantContext $context)
    {
    }

    /**
     * @param  array<string, mixed>|null  $old
     * @param  array<string, mixed>|null  $new
     */
    public function log(
        string $action,
        ?Model $subject = null,
        ?array $old = null,
        ?array $new = null,
        ?int $tenantId = null,
        ?int $branchId = null,
        ?int $actorId = null,
    ): AuditLog {
        $actor = Auth::user();

        $tenantId ??= $subject?->getAttribute('tenant_id')
            ?? $this->context->tenantId()
            ?? $actor?->tenant_id;

        $branchId ??= $subject?->getAttribute('branch_id');

        $log = new AuditLog([
            'action' => $action,
            'entity_type' => $subject !== null ? $subject->getMorphClass() : null,
            'entity_id' => $subject?->getKey(),
            'old_values' => $this->mask($old),
            'new_values' => $this->mask($new),
            'ip_address' => request()?->ip(),
            'user_agent' => mb_substr((string) request()?->userAgent(), 0, 512) ?: null,
        ]);

        $log->tenant_id = $tenantId;
        $log->branch_id = $branchId;
        // Aktör yoksa ve özne bir kullanıcıysa (auth akışları: reset, pin
        // kilidi vb.) olay o kullanıcıya yazılır.
        $log->user_id = $actorId
            ?? $actor?->getKey()
            ?? ($subject instanceof \App\Modules\Identity\Models\User ? $subject->getKey() : null);
        $log->save();

        return $log;
    }

    /**
     * @param  array<string, mixed>|null  $values
     * @return array<string, mixed>|null
     */
    private function mask(?array $values): ?array
    {
        if ($values === null) {
            return null;
        }

        foreach (self::MASKED as $key) {
            if (array_key_exists($key, $values)) {
                $values[$key] = '[gizli]';
            }
        }

        return $values;
    }
}
