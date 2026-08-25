<?php

namespace App\Modules\Tenancy\Models;

use Database\Factories\TenantFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Kiracı = sözleşme/müşteri (ör. bir belediye). ADR-004 hiyerarşi kökü.
 * Bu model kiracı-scoped DEĞİLDİR (kendisi kök); yönetimi yalnız
 * platform/konsol tarafında yapılır, panel rotalarına bağlanmaz.
 */
class Tenant extends Model
{
    /** @use HasFactory<TenantFactory> */
    use HasFactory;

    /** Kiracı yaşam döngüsü durumları. */
    public const STATUS_ACTIVE = 'active';
    public const STATUS_TRIAL = 'trial';
    public const STATUS_SUSPENDED = 'suspended';

    protected $fillable = [
        'name',
        'slug',
        'domain',
        'status',
        'plan',
        'trial_ends_at',
        'subscribed_until',
        'billing_note',
        'settings',
        'theme',
        'terminal_license_limit',
    ];

    protected function casts(): array
    {
        return [
            'settings' => 'array',
            'theme' => 'array',
            'trial_ends_at' => 'date',
            'subscribed_until' => 'date',
            // NULL = sınırsız (bilinçli istisna); bkz. config/terminal.php.
            'terminal_license_limit' => 'integer',
        ];
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    /** Panele erişebilir mi? Yalnız ASKIDAKİ işletme erişemez (deneme + aktif erişir). */
    public function isActive(): bool
    {
        return $this->status !== self::STATUS_SUSPENDED;
    }

    public function isSuspended(): bool
    {
        return $this->status === self::STATUS_SUSPENDED;
    }

    /** Askıya al (geri alınabilir; oturum ve veri korunur). */
    public function suspend(?string $note = null): void
    {
        $this->status = self::STATUS_SUSPENDED;
        if ($note !== null) {
            $this->billing_note = $note;
        }
        $this->save();
    }

    /** Yeniden aç. */
    public function activate(): void
    {
        $this->status = self::STATUS_ACTIVE;
        $this->save();
    }

    protected static function newFactory(): Factory
    {
        return TenantFactory::new();
    }
}
