<?php

namespace App\Modules\Identity\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Illuminate\Validation\ValidationException;

class PasswordResetController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /**
     * Sıfırlama bağlantısı iste. Yanıt her durumda aynıdır
     * (e-posta varlığı sızdırılmaz); 3 istek/dk sınırı vardır.
     */
    public function forgot(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'email']]);

        $key = 'pwreset:'.sha1(mb_strtolower($data['email']).'|'.$request->ip());

        if (RateLimiter::tooManyAttempts($key, 3)) {
            throw ValidationException::withMessages([
                'email' => ['Çok fazla istek. Lütfen sonra tekrar deneyin.'],
            ])->status(429);
        }

        RateLimiter::hit($key, 60);

        Password::broker()->sendResetLink(['email' => $data['email']]);

        return response()->json([
            'message' => 'Eğer bu e-posta kayıtlıysa bir sıfırlama bağlantısı gönderildi.',
        ]);
    }

    public function reset(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'email'],
            'password' => ['required', 'confirmed', PasswordRule::min(10)],
        ]);

        $status = Password::broker()->reset(
            $data,
            function (User $user, string $password): void {
                $user->forceFill(['password' => $password])->save();
                $this->audit->log('auth.password_reset', $user);
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            throw ValidationException::withMessages(['email' => [__($status)]]);
        }

        return response()->json(['message' => 'Parola güncellendi.']);
    }
}
