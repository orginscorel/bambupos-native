<?php

namespace App\Modules\Identity\Http\Middleware;

use App\Modules\Identity\Models\User;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Pasife alınan (işten çıkarılan) personelin AÇIK OTURUMU da düşürülür.
 * Login uçları zaten is_active=true süzer; bu katman oturumu süren
 * kullanıcıyı yakalar — pasifleştirme anında erişim biter.
 */
class EnsureUserIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user instanceof User && ! $user->is_active) {
            Auth::guard('web')->logout();

            if ($request->hasSession()) {
                $request->session()->invalidate();
                $request->session()->regenerateToken();
            }

            if ($request->is('api/*') || $request->expectsJson()) {
                return response()->json(['message' => 'Hesabınız pasif durumda. Yöneticinizle görüşün.'], 403);
            }

            return redirect('/giris');
        }

        return $next($request);
    }
}
