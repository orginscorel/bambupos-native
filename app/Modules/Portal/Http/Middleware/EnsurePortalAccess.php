<?php

namespace App\Modules\Portal\Http\Middleware;

use App\Modules\Identity\Models\User;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Personel Portalı erişim kapısı (portal rota grubuna özel).
 *
 * - Terminal (is_terminal) oturumları portala ALINMAZ: onların tek yüzeyi
 *   kilitli istasyon ekranıdır (§13). Portal, kişinin KENDİ self-servis
 *   yüzeyidir; cihaz kilidi ile karışmaz.
 * - Pasiflik/parola-değişimi oto-kapanması zaten EnsureUserIsActive +
 *   AuthenticateSession ile sağlanır (bu middleware onları tekrarlamaz).
 */
class EnsurePortalAccess
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user instanceof User && $user->is_terminal) {
            Auth::guard('web')->logout();

            if ($request->hasSession()) {
                $request->session()->invalidate();
                $request->session()->regenerateToken();
            }

            if ($request->expectsJson()) {
                return response()->json(['message' => 'Terminal cihazları personel portalını kullanamaz.'], 403);
            }

            return redirect('/giris');
        }

        return $next($request);
    }
}
