<?php

namespace App\Modules\Identity\Models;

use App\Modules\Tenancy\Scopes\TenantScope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use LogicException;

/**
 * Denetim kaydı — YALNIZ EKLENİR (append-only).
 *
 * - Okuma: TenantScope ile kiracıya süzülür (fail closed).
 * - Yazma: yalnız AuditLogger servisi; tenant_id null olabilir
 *   (başarısız/etkisiz girişler gibi kiracısız olaylar için).
 * - Güncelleme/silme MODEL DÜZEYİNDE yasaktır; uygulamada bu tabloya
 *   yazan hiçbir update/delete rotası yoktur.
 */
class AuditLog extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = [
        'action',
        'entity_type',
        'entity_id',
        'old_values',
        'new_values',
        'ip_address',
        'user_agent',
    ];

    protected function casts(): array
    {
        return [
            'old_values' => 'array',
            'new_values' => 'array',
        ];
    }

    protected static function booted(): void
    {
        static::addGlobalScope(new TenantScope);

        static::updating(function (): void {
            throw new LogicException('Denetim kayıtları değiştirilemez.');
        });

        static::deleting(function (): void {
            throw new LogicException('Denetim kayıtları silinemez.');
        });
    }

    /** Yalnız AuditLogger kullanır. */
    public static function withoutTenancy(): Builder
    {
        return static::query()->withoutGlobalScope(TenantScope::class);
    }
}
