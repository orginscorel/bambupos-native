<?php

namespace App\Modules\Tenancy\Http\Middleware;

use App\Modules\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Panel rotaları için kiracı bağlamını kurar ve hesap durumunu denetler.
 * Kiracı kimliği YALNIZ oturumdaki kullanıcıdan çözülür; istekten
 * gelen hiçbir tenant/branch parametresi bağlamı etkileyemez (ADR-004 katman 4).
 */
class EnsureTenantContext
{
    public function __construct(private readonly TenantContext $context)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user === null) {
            abort(401);
        }

        if (! $user->is_active) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();

            abort(403, 'Hesabınız pasif durumda.');
        }

        if ($user->tenant_id === null) {
            abort(403, 'Kullanıcının bağlı olduğu bir işletme yok.');
        }

        $tenant = $user->tenant;

        if ($tenant === null) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();

            abort(403, 'İşletme bulunamadı.');
        }

        // Askıdaki işletme: oturumu KORU (geri alınabilir), dostça askı ekranına yönlendir.
        // Aktifleşince kullanıcı kaldığı yerden devam eder — çıkış yaptırmayız.
        if ($tenant->isSuspended()) {
            if ($request->header('X-Inertia')) {
                return response('', 409)->header('X-Inertia-Location', route('tenant.suspended'));
            }
            if ($request->expectsJson()) {
                abort(402, 'İşletme hesabı askıda.');
            }

            return redirect()->route('tenant.suspended');
        }

        $this->context->setTenant($tenant);

        try {
            return $next($request);
        } finally {
            $this->context->forget();
        }
    }
}
