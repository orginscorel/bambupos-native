<?php

namespace App\Modules\Terminal\Models;

use App\Modules\Identity\Concerns\Auditable;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Support\Totp;
use App\Modules\Tenancy\Concerns\BelongsToTenant;
use App\Modules\Tenancy\Models\Branch;
use chillerlan\QRCode\Common\EccLevel;
use chillerlan\QRCode\Output\QROutputInterface;
use chillerlan\QRCode\QRCode;
use chillerlan\QRCode\QROptions;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * İstasyon terminal cihazı (§13, Faz A).
 *
 * Kimlik = opak token (kiosk/masa QR deseni, ADR-008): 26 karakter base32,
 * URL'de tek kimlik; kiracı/şube/istasyon HER ZAMAN token'dan çözülür.
 * Rotasyonda previous_token izi kalır (410 sayfası). Cihaz bir GİZLİ,
 * istasyona-atanmış terminal kullanıcısına (user_id) bağlıdır; token'la
 * açılınca o kullanıcının oturumu KİLİTLİ moddan başlar.
 */
class TerminalDevice extends Model
{
    use Auditable, BelongsToTenant;

    public const STATUS_ACTIVE = 'active';

    public const STATUS_INACTIVE = 'inactive';

    /** Bu süreden yeni bir kalp atışı = çevrimiçi (panel sağlık rozeti). */
    public const ONLINE_WINDOW_SECONDS = 180;

    protected $table = 'terminal_devices';

    protected $fillable = [
        'name',
        'station',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'locked_at' => 'datetime',
            'token_rotated_at' => 'datetime',
            'last_seen_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (self $device): void {
            $device->token ??= self::generateToken();
        });
    }

    public static function generateToken(): string
    {
        return substr(Totp::base32Encode(random_bytes(16)), 0, 26);
    }

    /** Eski token ANINDA geçersiz olur; iz 410 sayfası için saklanır. */
    public function rotateToken(): void
    {
        $this->previous_token = $this->token;
        $this->token = self::generateToken();
        $this->token_rotated_at = now();
        $this->save();
    }

    public function isLocked(): bool
    {
        return $this->status === self::STATUS_INACTIVE;
    }

    public function isOnline(): bool
    {
        return $this->last_seen_at !== null
            && $this->last_seen_at->gt(now()->subSeconds(self::ONLINE_WINDOW_SECONDS));
    }

    /** Terminal giriş adresi (cihaza bir kez girilir; token'la oto-giriş). */
    public function screenUrl(): string
    {
        return rtrim((string) config('app.url'), '/').'/terminal/'.$this->token;
    }

    /** Cihazda gösterilecek QR (giriş adresi) — SVG data URI. */
    public function qrDataUri(): string
    {
        $options = new QROptions([
            'outputType' => QROutputInterface::MARKUP_SVG,
            'eccLevel' => EccLevel::M,
            'addQuietzone' => true,
            'quietzoneSize' => 2,
            'outputBase64' => true,
        ]);

        return (new QRCode($options))->render($this->screenUrl());
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
