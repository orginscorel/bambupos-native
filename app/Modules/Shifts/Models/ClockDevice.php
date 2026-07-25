<?php

namespace App\Modules\Shifts\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Yetkili giriş/çıkış cihazı (kiosk/tablet).
 * Token yalnız SHA-256 hash olarak saklanır; düz metin bir kez gösterilir.
 */
class ClockDevice extends Model
{
    use Auditable, BelongsToTenant;

    protected $fillable = ['branch_id', 'name', 'is_active'];

    protected $hidden = ['token_hash'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'last_seen_at' => 'datetime',
        ];
    }

    public static function hashToken(string $token): string
    {
        return hash('sha256', $token);
    }

    /**
     * Token'dan cihaz çözer (kiracıdan bağımsız arama — cihaz isteği
     * oturumsuzdur; kiracı kimliği CİHAZDAN gelir, istekten değil).
     */
    public static function findByToken(string $token): ?self
    {
        return static::withoutTenancy()
            ->where('token_hash', self::hashToken($token))
            ->where('is_active', true)
            ->first();
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
