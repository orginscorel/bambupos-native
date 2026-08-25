<?php

namespace App\Modules\Devices\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * İzinli Cihaz (A3 — KDS/Kiosk/Terminal cihaz kilidi temeli).
 *
 * Bir satır = "bir link/kaynak BİR tarayıcıya kilitli" eşleşmesi.
 *  - device_token: tarayıcıda (çerez/localStorage) saklanan opak sır (uuid).
 *  - bound_link  : hangi ekrana/kaynağa kilitli olduğu (route adı/token gibi
 *                  bir tanımlayıcı); NULL ise henüz hiçbir ekrana bağlanmamış
 *                  "ön-yetkili" bir satırdır (bkz. DeviceBindingService::provision).
 *  - status      : active | revoked. Revoked → hiçbir eşleşme kabul edilmez.
 *
 * Bağlama/serbest bırakma mantığı KASITLI OLARAK bu modelde DEĞİL,
 * DeviceBindingService'te toplanmıştır (eşzamanlılık + transaction orada
 * yönetilir). Model yalnız durum sorguları ve basit alan güncellemeleri sunar.
 */
class AuthorizedDevice extends Model
{
    use Auditable, BelongsToTenant;

    public const KIND_KDS = 'kds';

    public const KIND_KIOSK = 'kiosk';

    public const KIND_DESKTOP = 'desktop';

    public const KIND_TERMINAL = 'terminal';

    public const KINDS = [self::KIND_KDS, self::KIND_KIOSK, self::KIND_DESKTOP, self::KIND_TERMINAL];

    public const STATUS_ACTIVE = 'active';

    public const STATUS_REVOKED = 'revoked';

    protected $table = 'authorized_devices';

    protected $fillable = [
        'kind',
        'name',
        'bound_link',
        'status',
        'meta',
    ];

    protected function casts(): array
    {
        return [
            'last_seen_at' => 'datetime',
            'first_bound_at' => 'datetime',
            'meta' => 'array',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (self $device): void {
            $device->device_token ??= self::generateToken();
            $device->status ??= self::STATUS_ACTIVE;
        });
    }

    public static function generateToken(): string
    {
        return (string) Str::uuid();
    }

    public function isActive(): bool
    {
        return $this->status === self::STATUS_ACTIVE;
    }

    public function isRevoked(): bool
    {
        return $this->status === self::STATUS_REVOKED;
    }

    /** Bir tarayıcıya bağlanmış mı (ilk ziyaret gerçekleşmiş mi)? */
    public function isBound(): bool
    {
        return $this->bound_link !== null && $this->first_bound_at !== null;
    }

    /** Bu süreden yeni bir görülme = çevrimiçi (panel sağlık rozeti — kiosk/terminal deseniyle aynı). */
    public const ONLINE_WINDOW_SECONDS = 180;

    public function isOnline(): bool
    {
        return $this->last_seen_at !== null
            && $this->last_seen_at->gt(now()->subSeconds(self::ONLINE_WINDOW_SECONDS));
    }
}
