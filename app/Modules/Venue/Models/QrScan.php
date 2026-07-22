<?php

namespace App\Modules\Venue\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Prunable;

/**
 * QR tarama günlüğü (ADR-008). Public uçta kiracı bağlamı OLMADAN yazılır;
 * bu yüzden BelongsToTenant kullanılmaz (fail-closed scope public yazımı
 * engellerdi). Kişisel veri yok: IP SHA-256 ile hash'lenir.
 */
class QrScan extends Model
{
    use Prunable;

    public const UPDATED_AT = null;

    protected $table = 'qr_scans';

    protected $fillable = [
        'tenant_id',
        'table_id',
        'token',
        'result',
        'ip_hash',
        'user_agent',
    ];

    /** 30 günden eski tarama günlükleri `model:prune` ile temizlenir. */
    public function prunable(): Builder
    {
        return static::query()->where('created_at', '<', now()->subDays(30));
    }

    public static function hashIp(?string $ip): string
    {
        return hash('sha256', (string) $ip.config('app.key'));
    }
}
