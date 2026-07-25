<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Support\Totp;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * İki faktörlü doğrulama (TOTP) — hazır yapı, v1'de zorunlu değil.
 */
class TwoFactorController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /** Kurulumu başlat: secret üret (henüz doğrulanmadı). */
    public function enable(Request $request): JsonResponse
    {
        $user = $request->user();

        $secret = Totp::generateSecret();

        $user->forceFill([
            'two_factor_secret' => $secret,
            'two_factor_confirmed_at' => null,
            'two_factor_recovery_codes' => null,
        ])->save();

        return response()->json([
            'secret' => $secret,
            'otpauth_url' => Totp::otpauthUrl($secret, $user->email),
        ]);
    }

    /** Kod doğrulanırsa 2FA aktifleşir; kurtarma kodları BİR KEZ döner. */
    public function confirm(Request $request): JsonResponse
    {
        $data = $request->validate(['code' => ['required', 'string']]);

        $user = $request->user();

        if ($user->two_factor_secret === null || ! Totp::verify($user->two_factor_secret, $data['code'])) {
            throw ValidationException::withMessages(['code' => ['Kod doğrulanamadı.']]);
        }

        $recoveryCodes = collect(range(1, 8))
            ->map(fn () => Str::upper(Str::random(5)).'-'.Str::upper(Str::random(5)))
            ->all();

        $user->forceFill([
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => $recoveryCodes,
        ])->save();

        $this->audit->log('auth.two_factor_enabled', $user);

        return response()->json(['recovery_codes' => $recoveryCodes]);
    }

    public function disable(Request $request): JsonResponse
    {
        $data = $request->validate(['password' => ['required', 'string', 'current_password:web']]);

        $user = $request->user();

        $user->forceFill([
            'two_factor_secret' => null,
            'two_factor_recovery_codes' => null,
            'two_factor_confirmed_at' => null,
        ])->save();

        $this->audit->log('auth.two_factor_disabled', $user);

        return response()->json(['ok' => true]);
    }

    /** Login sonrası challenge: TOTP kodu ya da kurtarma kodu. */
    public function challenge(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string'],
        ]);

        $userId = $request->session()->get('auth.2fa.user_id');

        if ($userId === null) {
            throw ValidationException::withMessages(['code' => ['Bekleyen bir iki faktör doğrulaması yok.']])->status(422);
        }

        $key = '2fa:'.$userId.'|'.$request->ip();

        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages([
                'code' => ['Çok fazla deneme. Lütfen sonra tekrar deneyin.'],
            ])->status(429);
        }

        $user = User::query()->find($userId);

        if ($user === null || ! $user->hasTwoFactorEnabled()) {
            throw ValidationException::withMessages(['code' => ['Doğrulama başarısız.']]);
        }

        $valid = Totp::verify($user->two_factor_secret, $data['code']);

        if (! $valid) {
            $codes = $user->two_factor_recovery_codes ?? [];
            $index = array_search(strtoupper(trim($data['code'])), array_map('strtoupper', $codes), true);

            if ($index !== false) {
                unset($codes[$index]);
                $user->forceFill(['two_factor_recovery_codes' => array_values($codes)])->save();
                $valid = true;
                $this->audit->log('auth.two_factor_recovery_used', $user);
            }
        }

        if (! $valid) {
            RateLimiter::hit($key, 60);

            throw ValidationException::withMessages(['code' => ['Kod doğrulanamadı.']]);
        }

        RateLimiter::clear($key);

        $remember = (bool) $request->session()->pull('auth.2fa.remember', false);
        $request->session()->forget('auth.2fa.user_id');

        Auth::guard('web')->login($user, $remember);
        $request->session()->regenerate();

        $user->forceFill(['last_login_at' => now(), 'last_login_ip' => $request->ip()])->save();

        $this->audit->log('auth.login', $user);

        return response()->json(['user' => $user->only(['id', 'name', 'email', 'locale', 'theme'])]);
    }
}
