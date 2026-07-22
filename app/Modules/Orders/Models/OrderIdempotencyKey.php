<?php

namespace App\Modules\Orders\Models;

use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/** Idempotency anahtarı — UNIQUE(tenant_id, key); bkz. IdempotencyStore. */
class OrderIdempotencyKey extends Model
{
    use BelongsToTenant;

    protected $fillable = [
        'key',
        'endpoint',
    ];

    protected function casts(): array
    {
        return [
            'response' => 'array',
            'status_code' => 'integer',
        ];
    }
}
