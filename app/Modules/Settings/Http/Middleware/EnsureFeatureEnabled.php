<?php

namespace App\Modules\Settings\Http\Middleware;

use App\Modules\Settings\Support\Features;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Rota düzeyinde ÖZELLİK (feature-flag) kapısı: `feature:delivery` gibi.
 *
 * Kiracıda ilgili özellik KAPALIYSA rota YOK gibi 404 döner — "kapalı = yok"
 * (ADR/§9) kuralını yalnız sayfa kabuğunda değil, API dâhil tüm rota grubunda
 * garanti eder. Oturum + kiracı bağlamından SONRA çalışmalı (tenant_id gerekir).
 */
class EnsureFeatureEnabled
{
    public function handle(Request $request, Closure $next, string $feature): Response
    {
        $tenantId = $request->user()?->tenant_id;

        abort_unless($tenantId !== null && Features::enabled((int) $tenantId, $feature), 404);

        return $next($request);
    }
}
