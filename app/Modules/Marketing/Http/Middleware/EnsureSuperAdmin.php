<?php

namespace App\Modules\Marketing\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * SaaS süper-admin kapısı: yalnız users.is_super_admin=true erişir.
 * Kiracı-üstüdür — `tenant` middleware'i KULLANMAZ (tüm işletmeleri görür).
 */
class EnsureSuperAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user || ! $user->is_super_admin) {
            abort(403, 'Bu alana yalnız BamBumPOS yöneticileri erişebilir.');
        }

        return $next($request);
    }
}
