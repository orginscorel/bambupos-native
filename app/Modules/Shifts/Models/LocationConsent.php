<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Models\User;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * KVKK açık rıza kaydı (konum). Personelin KENDİ verdiği rızadır;
 * dilediği an geri çeker (revoked_at). Rıza yokken konum ASLA yazılmaz.
 */
class LocationConsent extends Model
{
    use BelongsToTenant;

    protected $table = 'shift_location_consents';

    protected $fillable = ['user_id', 'consented_at', 'revoked_at'];

    protected function casts(): array
    {
        return [
            'consented_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function isActive(): bool
    {
        return $this->revoked_at === null;
    }

    public static function activeFor(int $userId): bool
    {
        return static::query()
            ->where('user_id', $userId)
            ->whereNull('revoked_at')
            ->exists();
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
