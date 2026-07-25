<?php

namespace App\Http\Middleware;

use Illuminate\Http\Request;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * The root template that's loaded on the first page visit.
     *
     * @see https://inertiajs.com/server-side-setup#root-template
     *
     * @var string
     */
    protected $rootView = 'app';

    /**
     * Determines the current asset version.
     *
     * @see https://inertiajs.com/asset-versioning
     */
    public function version(Request $request): ?string
    {
        return parent::version($request);
    }

    /**
     * Define the props that are shared by default.
     *
     * @see https://inertiajs.com/shared-data
     *
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        return [
            ...parent::share($request),

            // Closure yalnız Inertia yanıtı üretilirken çalışır;
            // /api/v1 JSON isteklerine ek sorgu maliyeti binmez.
            'auth' => fn () => $this->authPayload($request),

            // Personel taklidi aktifse: kalıcı şerit için görüntülenen kişinin adı
            // (aktif kullanıcı = taklit edilen personel). Aksi hâlde null.
            'impersonating' => fn () => $this->impersonatingPayload($request),
        ];
    }

    /**
     * Taklit oturumu aktifse görüntülenen personelin adını döndürür.
     *
     * @return array{name: string|null}|null
     */
    private function impersonatingPayload(Request $request): ?array
    {
        if (! $request->hasSession() || $request->session()->get('impersonator_id') === null) {
            return null;
        }

        $user = $request->user();

        if ($user === null) {
            return null;
        }

        return ['name' => $user->name];
    }

    /**
     * Panel kabuğunun ihtiyacı: kullanıcı, izinler, kiracı, şubeler, aktif şube.
     *
     * @return array<string, mixed>|null
     */
    private function authPayload(Request $request): ?array
    {
        /** @var \App\Modules\Identity\Models\User|null $user */
        $user = $request->user();

        if ($user === null) {
            return null;
        }

        $tenant = $user->tenant;

        $branches = $tenant === null
            ? collect()
            : \App\Modules\Tenancy\Models\Branch::query()
                ->withoutGlobalScopes()
                ->where('tenant_id', $tenant->getKey())
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name', 'code', 'timezone']); // timezone: panel saati şube dilimine göre gösterir

        $activeBranchId = (int) ($request->session()->get('panel.active_branch_id') ?: $user->branch_id);

        if (! $branches->contains(fn ($b) => (int) $b->id === $activeBranchId)) {
            $activeBranchId = (int) ($branches->first()->id ?? 0);
        }

        return [
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'first_name' => $user->first_name,
                'last_name' => $user->last_name,
                'email' => $user->email,
                'staff_code' => $user->staff_code,
                'position' => $user->position,
                'theme' => $user->theme,
                'last_login_at' => $user->last_login_at?->toIso8601String(),
                'two_factor_enabled' => $user->hasTwoFactorEnabled(),
                'has_pin' => $user->pin_hash !== null,
                'default_screen' => $user->default_screen,
                'roles' => $user->roles()
                    ->withoutGlobalScopes()
                    ->where('roles.tenant_id', $user->tenant_id)
                    ->pluck('name'),
            ],
            'permissions' => $user->permissionKeys(),
            // Açılış ekranı tercih listesi (yalnız izinli ekranlar)
            'screenOptions' => \App\Modules\Identity\Support\HomeScreen::optionsFor($user),
            'tenant' => $tenant?->only(['name', 'slug']),
            'branches' => $branches,
            'activeBranchId' => $activeBranchId ?: null,
        ];
    }
}
