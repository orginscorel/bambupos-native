<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

class LoginController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /**
     * E-posta + parola girişi.
     * - Başarısız giriş sınırı: 5 deneme/dk (e-posta+IP anahtarı), başarıda sıfırlanır.
     * - Aynı e-posta birden çok kiracıda olabilir (UNIQUE(tenant_id, email));
     *   parola hangi kullanıcıda doğrulanırsa o kullanıcı girer.
     * - 2FA etkinse oturum açılmaz; challenge beklenir.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'remember' => ['sometimes', 'boolean'],
        ]);

        $key = $this->throttleKey($request, $data['email']);

        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages([
                'email' => ['Çok fazla giriş denemesi. Lütfen '.RateLimiter::availableIn($key).' saniye sonra tekrar deneyin.'],
            ])->status(429);
        }

        $candidates = User::query()
            ->where('email', $data['email'])
            ->where('is_active', true)
            // §13: gizli terminal kullanıcıları normal (e-posta/parola) giriş
            // YAPAMAZ — tek giriş kapıları /terminal/{token} oto-girişidir.
            ->where('is_terminal', false)
            ->get();

        $user = $candidates->first(fn (User $u) => Hash::check($data['password'], $u->password));

        if ($user === null) {
            RateLimiter::hit($key, 60);
            $this->audit->log('auth.login_failed', null, null, ['email' => $data['email']]);

            throw ValidationException::withMessages(['email' => [__('auth.failed')]]);
        }

        if ($user->tenant_id !== null && (! $user->tenant || ! $user->tenant->isActive())) {
            RateLimiter::hit($key, 60);

            throw ValidationException::withMessages([
                'email' => ['İşletme hesabı askıda.'],
            ])->status(403);
        }

        RateLimiter::clear($key);

        // Personel Portalı KALICI oturum: portal host'undan yapılan girişte
        // uzun ömürlü "beni hatırla" zorlanır (idle-timeout yok; oturum yalnız
        // pasiflik/parola-değişiminde düşer). Panel host'unda davranış DEĞİŞMEZ.
        $remember = (bool) ($data['remember'] ?? false);

        if (\App\Modules\Portal\Support\Portal::forcesRemember()
            && \App\Modules\Portal\Support\Portal::isPortalHost($request)) {
            $remember = true;
        }

        // Patron Paneli (patron.*) da personel portalı gibi KALICI oturum kullanır.
        if (\App\Modules\Boss\Support\BossHost::forcesRemember()
            && \App\Modules\Boss\Support\BossHost::isBossHost($request)) {
            $remember = true;
        }

        if ($user->hasTwoFactorEnabled()) {
            $request->session()->put('auth.2fa.user_id', $user->getKey());
            $request->session()->put('auth.2fa.remember', $remember);

            return response()->json(['two_factor' => true]);
        }

        $this->completeLogin($request, $user, $remember);

        // Patron host'unda (patron.*) giriş → Patron Paneli kökü (/). Aksi hâlde
        // role özel açılış ekranı (garson→sipariş, kasiyer→kasa, mutfak→KDS,
        // yönetici→panel — Personel-Yetki).
        $redirectTo = \App\Modules\Boss\Support\BossHost::isBossHost($request)
            ? '/'
            : \App\Modules\Identity\Support\HomeScreen::resolve($user);

        return response()->json([
            'two_factor' => false,
            'user' => $user->only(['id', 'name', 'email', 'locale', 'theme']),
            'redirect_to' => $redirectTo,
        ]);
    }

    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user !== null) {
            $this->audit->log('auth.logout', $user);
        }

        Auth::guard('web')->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return response()->json(['ok' => true]);
    }

    private function completeLogin(Request $request, User $user, bool $remember): void
    {
        Auth::guard('web')->login($user, $remember);

        $request->session()->regenerate();

        $user->forceFill([
            'last_login_at' => now(),
            'last_login_ip' => $request->ip(),
        ])->save();

        $this->audit->log('auth.login', $user);
    }

    private function throttleKey(Request $request, string $email): string
    {
        return 'login:'.sha1(mb_strtolower($email).'|'.$request->ip());
    }
}
