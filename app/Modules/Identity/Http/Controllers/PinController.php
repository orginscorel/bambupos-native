<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Identity\Services\PinService;
use App\Modules\Tenancy\Models\Tenant;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

class PinController extends Controller
{
    public function __construct(
        private readonly PinService $pins,
        private readonly AuditLogger $audit,
    ) {
    }

    /** Oturumdaki kullanıcı kendi PIN'ini belirler (parola doğrulamalı). */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'password' => ['required', 'string', 'current_password:web'],
            'pin' => ['required', 'string'],
        ]);

        $this->pins->setPin($request->user(), $data['pin']);

        return response()->json(['ok' => true]);
    }

    /**
     * Personel hızlı PIN girişi: işletme (slug) + personel kodu + PIN.
     * Deneme sınırı hem RateLimiter (IP+kod) hem kullanıcı-üstü kilit ile.
     */
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'tenant' => ['required', 'string'],
            'staff_code' => ['required', 'string'],
            'pin' => ['required', 'string'],
        ]);

        $key = 'pin:'.sha1($data['tenant'].'|'.$data['staff_code'].'|'.$request->ip());

        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages([
                'pin' => ['Çok fazla deneme. Lütfen '.RateLimiter::availableIn($key).' saniye sonra tekrar deneyin.'],
            ])->status(429);
        }

        $tenant = Tenant::query()->where('slug', $data['tenant'])->where('status', 'active')->first();

        $user = $tenant === null ? null : User::query()
            ->where('tenant_id', $tenant->getKey())
            ->where('staff_code', $data['staff_code'])
            ->where('is_active', true)
            ->first();

        if ($user === null || ! $this->pins->verify($user, $data['pin'])) {
            RateLimiter::hit($key, 60);

            if ($user !== null) {
                $this->audit->log('auth.pin_failed', $user);
            }

            throw ValidationException::withMessages(['pin' => ['Giriş bilgileri doğrulanamadı.']]);
        }

        RateLimiter::clear($key);

        Auth::guard('web')->login($user); // PIN girişinde "beni hatırla" yok (bilinçli)
        $request->session()->regenerate();

        $user->forceFill(['last_login_at' => now(), 'last_login_ip' => $request->ip()])->save();

        $this->audit->log('auth.pin_login', $user);

        return response()->json([
            'user' => $user->only(['id', 'name', 'email', 'locale', 'theme']),
            'redirect_to' => \App\Modules\Identity\Support\HomeScreen::resolve($user),
        ]);
    }
}
