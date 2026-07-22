<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\Permission;
use App\Modules\Identity\Models\Role;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Services\PinService;
use App\Modules\Identity\Services\StaffService;
use App\Modules\Identity\Support\HomeScreen;
use App\Modules\Identity\Support\RoleTemplates;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

/**
 * Personel-Yetki ajanı: personel ekranlarının JSON uçları.
 *  - meta: izin kataloğu + roller + şablonlar + tehlikeli izinler + ekranlar
 *  - kişi bazlı izin istisnaları (grant/revoke)
 *  - yönetici eliyle PIN belirleme/temizleme
 *  - parola sıfırlama bağlantısı gönderme
 *  - işten çıkarma (pasife alma) / yeniden aktifleştirme
 */
class StaffAccessController extends Controller
{
    public function __construct(
        private readonly StaffService $staff,
        private readonly PinService $pins,
        private readonly AuditLogger $audit,
    ) {
    }

    /** Personel + rol ekranlarının ortak sözlüğü. */
    public function meta(Request $request): JsonResponse
    {
        $user = $request->user();

        // staff.view VEYA roles.view yeterli (iki sekme de bu ucu kullanır)
        if (! $user->hasPermission('staff.view') && ! $user->hasPermission('roles.view') && ! $user->hasPermission('roles.manage')) {
            abort(403);
        }

        $moduleLabels = (array) config('authz.module_labels', []);
        $actionLabels = (array) config('authz.labels', []);
        $dangerous = (array) config('authz.dangerous', []);

        $idsByKey = Permission::query()->pluck('id', 'key');

        $catalog = [];

        foreach ((array) config('authz.modules', []) as $module => $actions) {
            $catalog[] = [
                'module' => $module,
                'label' => $moduleLabels[$module] ?? ucfirst($module),
                'permissions' => array_map(fn (string $action) => [
                    'id' => $idsByKey["{$module}.{$action}"] ?? null,
                    'key' => "{$module}.{$action}",
                    'action' => $action,
                    'label' => $actionLabels[$action] ?? ucfirst($action),
                    'dangerous' => isset($dangerous["{$module}.{$action}"]),
                    'warning' => $dangerous["{$module}.{$action}"] ?? null,
                ], $actions),
            ];
        }

        $templates = array_map(fn (array $t, string $key) => [
            'key' => $key,
            'name' => $t['name'],
            'description' => $t['description'],
            'permissions' => $t['permissions'],
        ], RoleTemplates::all(), array_keys(RoleTemplates::all()));

        return response()->json([
            'catalog' => $catalog,
            'roles' => Role::query()
                ->withCount('users')
                ->with('permissions:id,key')
                ->orderByDesc('is_system')
                ->orderBy('name')
                ->get()
                ->map(fn (Role $role) => [
                    'id' => $role->id,
                    'name' => $role->name,
                    'description' => $role->description,
                    'is_system' => (bool) $role->is_system,
                    'users_count' => $role->users_count,
                    'permission_keys' => $role->permissions->pluck('key')->values(),
                ]),
            'templates' => array_values($templates),
            'branches' => Branch::query()->orderBy('name')->get(['id', 'name', 'code']),
            'screens' => collect((array) config('authz.screens', []))
                ->map(fn (array $s, string $key) => ['key' => $key, 'label' => $s['label'], 'permission' => $s['permission']])
                ->values(),
            'actor' => [
                'id' => $user->id,
                'permissions' => $user->permissionKeys(),
                'can_manage_staff' => $user->hasPermission('staff.manage'),
                'can_manage_roles' => $user->hasPermission('roles.manage'),
            ],
        ]);
    }

    /** Kişi bazlı izin istisnalarını TAM SET olarak yazar. */
    public function setOverrides(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $data = $request->validate([
            'grants' => ['present', 'array'],
            'grants.*' => ['string', 'max:101'],
            'revokes' => ['present', 'array'],
            'revokes.*' => ['string', 'max:101'],
        ]);

        $staff = $this->staff->setPersonalPermissions($request->user(), $staff, $data['grants'], $data['revokes']);

        return response()->json([
            'overrides' => $staff->personalOverrideKeys(),
            'effective_permissions' => $staff->fresh()->permissionKeys(),
        ]);
    }

    /** Yönetici eliyle PIN belirleme (personel kartındaki "PIN belirle"). */
    public function setPin(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $data = $request->validate(['pin' => ['required', 'string']]);

        $this->pins->setPin($staff, $data['pin']);

        $this->audit->log('staff.pin_set_by_admin', $staff);

        return response()->json(['ok' => true, 'has_pin' => true]);
    }

    /** PIN'i kaldırır (personel PIN ile giremez olur). */
    public function clearPin(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $staff->forceFill([
            'pin_hash' => null,
            'failed_pin_attempts' => 0,
            'pin_locked_until' => null,
        ])->save();

        $this->audit->log('staff.pin_cleared_by_admin', $staff);

        return response()->json(['ok' => true, 'has_pin' => false]);
    }

    /** Personele parola sıfırlama bağlantısı e-postalar. */
    public function sendResetLink(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $key = 'staff-pwreset:'.$staff->getKey();

        if (RateLimiter::tooManyAttempts($key, 3)) {
            throw ValidationException::withMessages([
                'staff' => ['Bu personel için kısa süre önce bağlantı gönderildi. Lütfen bekleyin.'],
            ])->status(429);
        }

        RateLimiter::hit($key, 300);

        Password::broker()->sendResetLink(['email' => $staff->email]);

        $this->audit->log('staff.reset_link_sent', $staff);

        return response()->json(['message' => 'Sıfırlama bağlantısı e-posta ile gönderildi.']);
    }

    /** İşten çıkarma: silme DEĞİL, pasife alma (veri kaybı yok). */
    public function terminate(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $staff = $this->staff->terminate($request->user(), $staff);

        return response()->json(['ok' => true, 'user' => $staff->only(['id', 'is_active'])]);
    }

    /** Pasif personeli yeniden aktifleştirir. */
    public function activate(Request $request, User $staff): JsonResponse
    {
        $this->authorize('update', $staff);

        $staff->is_active = true;
        $staff->save();

        $this->audit->log('staff.reactivated', $staff, ['is_active' => false], ['is_active' => true]);

        return response()->json(['ok' => true, 'user' => $staff->only(['id', 'is_active'])]);
    }

    /** Bir personelin etkili izinleri + istisna kaynakları (detay paneli). */
    public function effective(Request $request, User $staff): JsonResponse
    {
        $this->authorize('view', $staff);

        $roleKeys = $staff->roles()
            ->withoutGlobalScope(\App\Modules\Tenancy\Scopes\TenantScope::class)
            ->where('roles.tenant_id', $staff->tenant_id)
            ->with('permissions:id,key')
            ->get()
            ->flatMap(fn (Role $role) => $role->permissions->pluck('key'))
            ->unique()
            ->values();

        return response()->json([
            'role_permissions' => $roleKeys,
            'overrides' => $staff->personalOverrideKeys(),
            'effective_permissions' => $staff->permissionKeys(),
            'home_screen' => HomeScreen::resolve($staff),
            'screen_options' => HomeScreen::optionsFor($staff),
        ]);
    }
}
