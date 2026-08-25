<?php

namespace App\Support\Idempotency\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/**
 * Modül-bağımsız op_id idempotency kaydı — UNIQUE(tenant_id, op_id).
 * bkz. App\Support\Idempotency\IdempotentRequest ve docs/offline-sync-protocol.md.
 */
class IdempotencyKey extends Model
{
    use BelongsToTenant;

    /** Yalnız created_at (append-only iddia kaydı; updated_at yok — bkz. migration). */
    public $timestamps = false;

    protected $table = 'idempotency_keys';

    protected $fillable = [
        'op_id',
        'scope',
        'request_hash',
        'status',
        'response_snapshot',
        'created_at',
    ];

    protected function casts(): array
    {
        return [
            'response_snapshot' => 'array',
            'created_at' => 'datetime',
        ];
    }
}
