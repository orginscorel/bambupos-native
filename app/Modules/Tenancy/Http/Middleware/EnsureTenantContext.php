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

        if ($tenant === null || ! $tenant->isActive()) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();

            abort(403, 'İşletme hesabı askıda.');
        }

        $this->context->setTenant($tenant);

        try {
            return $next($request);
        } finally {
            $this->context->forget();
        }
    }
}
