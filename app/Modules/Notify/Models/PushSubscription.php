<?php

namespace App\Modules\Notify\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Tarayıcı web-push aboneliği (§8). Cihaz başına tekil endpoint. Ölü abonelik
 * (push servisi 404/410) WebPushSender tarafından budanır.
 */
class PushSubscription extends Model
{
    use BelongsToTenant;

    protected $table = 'push_subscriptions';

    protected $fillable = [
        'user_id', 'endpoint', 'endpoint_hash', 'p256dh', 'auth', 'ua', 'last_used_at',
    ];

    protected function casts(): array
    {
        return ['last_used_at' => 'datetime'];
    }

    public static function hashEndpoint(string $endpoint): string
    {
        return hash('sha256', $endpoint);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
