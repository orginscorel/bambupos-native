<?php

namespace App\Modules\Identity\Models;

use App\Modules\Tenancy\Models\Branch;
use App\Modules\Tenancy\Models\Tenant;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Auth;

/**
 * Personel/kullanıcı modeli.
 *
 * DİKKAT — bilinçli istisna: User modeli BelongsToTenant global scope'unu
 * KULLANMAZ; çünkü oturum çözümlemesi (guard) kullanıcıyı sorgularken kiracı
 * bağlamı henüz kurulamaz (tavuk-yumurta). İzolasyon bu modelde şu katmanlarla
 * sağlanır:
 *  - route model binding: resolveRouteBinding() kiracı süzgeci uygular (404),
 *  - policy: StaffPolicy tenant eşitliğini doğrular,
 *  - servis katmanı: personel listeleri daima scopeOfCurrentTenant() ile çekilir.
 */
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    protected $fillable = [
        'first_name',
        'last_name',
        'email',
        'phone',
        'password',
        'staff_code',
        'department',
        'position',
        'hired_at',
        'locale',
        'theme',
        'default_screen',
        'is_active',
        'is_super_admin',
        'salary_type',
        'salary_amount_minor',
    ];

    protected $hidden = [
        'password',
        'remember_token',
        'pin_hash',
        'pin_encrypted',
        'two_factor_secret',
        'two_factor_recovery_codes',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_active' => 'boolean',
            'is_super_admin' => 'boolean',
            // §13 Terminal cihaz modu: gizli, istasyona-atanmış kullanıcı.
            // is_terminal BİLİNÇLİ olarak $fillable DIŞINDA — yalnız
            // TerminalProvisioner set eder; personel formundan atanamaz.
            'is_terminal' => 'boolean',
            'hired_at' => 'date',
            'salary_amount_minor' => 'integer',
            'last_login_at' => 'datetime',
            'pin_locked_until' => 'datetime',
            'two_factor_secret' => 'encrypted',
            'two_factor_recovery_codes' => 'encrypted:array',
            'two_factor_confirmed_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::saving(function (self $user): void {
            if ($user->first_name !== null || $user->last_name !== null) {
                $user->name = trim(($user->first_name ?? '').' '.($user->last_name ?? ''));
            }
        });
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(Role::class, 'role_user')->withTimestamps();
    }

    /**
     * Kişi bazlı izin istisnaları (pivot.mode: grant | revoke).
     * Etkili izin = (rollerin birleşimi + grant) − revoke.
     */
    public function personalPermissions(): BelongsToMany
    {
        return $this->belongsToMany(Permission::class, 'permission_user')
            ->withPivot('mode')
            ->withTimestamps();
    }

    /* ---------------- Yetki ---------------- */

    /** @var array<int, string>|null istek-içi izin önbelleği */
    private ?array $permissionKeyCache = null;

    /** @return array<int, string> */
    public function permissionKeys(): array
    {
        if ($this->permissionKeyCache !== null) {
            return $this->permissionKeyCache;
        }

        // TenantScope bağlama bağlıdır; burada bağlamdan bağımsız ama yine
        // kiracı-denetimli sorgu kullanılır: rol, kullanıcının KENDİ
        // kiracısına ait değilse izin vermez (çapraz rol ataması etkisiz).
        $fromRoles = $this->roles()
            ->withoutGlobalScope(\App\Modules\Tenancy\Scopes\TenantScope::class)
            ->where('roles.tenant_id', $this->tenant_id)
            ->with('permissions:id,key')
            ->get()
            ->flatMap(fn (Role $role) => $role->permissions->pluck('key'));

        // Kişi bazlı istisnalar: grant üstüne eklenir, revoke düşülür.
        $overrides = $this->personalPermissions()->get(['permissions.id', 'permissions.key']);

        $grants = $overrides->where('pivot.mode', 'grant')->pluck('key');
        $revokes = $overrides->where('pivot.mode', 'revoke')->pluck('key')->all();

        return $this->permissionKeyCache = $fromRoles
            ->merge($grants)
            ->unique()
            ->reject(fn (string $key) => in_array($key, $revokes, true))
            ->values()
            ->all();
    }

    /**
     * İstisnaların ham hâli (UI "rolden geliyor / kişiye özel" rozeti için).
     *
     * @return array{grant: array<int, string>, revoke: array<int, string>}
     */
    public function personalOverrideKeys(): array
    {
        $overrides = $this->personalPermissions()->get(['permissions.id', 'permissions.key']);

        return [
            'grant' => $overrides->where('pivot.mode', 'grant')->pluck('key')->values()->all(),
            'revoke' => $overrides->where('pivot.mode', 'revoke')->pluck('key')->values()->all(),
        ];
    }

    public function hasPermission(string $key): bool
    {
        return in_array($key, $this->permissionKeys(), true);
    }

    public function flushPermissionCache(): void
    {
        $this->permissionKeyCache = null;
    }

    /* ---------------- Kimlik yardımcıları ---------------- */

    public function hasTwoFactorEnabled(): bool
    {
        return $this->two_factor_confirmed_at !== null && $this->two_factor_secret !== null;
    }

    public function pinIsLocked(): bool
    {
        return $this->pin_locked_until !== null && $this->pin_locked_until->isFuture();
    }

    /* ---------------- İzolasyon (katman 3: route binding) ---------------- */

    public function resolveRouteBinding($value, $field = null)
    {
        $query = static::query()->where($field ?? $this->getRouteKeyName(), $value);

        $actor = Auth::user();

        // Oturum yoksa ya da aktör kiracısızsa hiçbir kullanıcı çözülmez (fail closed).
        if ($actor === null || $actor->tenant_id === null) {
            return null;
        }

        return $query->where('tenant_id', $actor->tenant_id)->first();
    }

    /** Servis katmanı için: daima bağlamdaki kiracıya süzülmüş sorgu. */
    public static function ofCurrentTenant(): \Illuminate\Database\Eloquent\Builder
    {
        $tenantId = app(\App\Modules\Tenancy\TenantContext::class)->tenantId();

        $query = static::query();

        if ($tenantId === null) {
            return $query->whereRaw('1 = 0');
        }

        return $query->where('tenant_id', $tenantId);
    }

    protected static function newFactory(): Factory
    {
        return UserFactory::new();
    }
}
