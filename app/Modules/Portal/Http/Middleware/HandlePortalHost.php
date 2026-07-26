<?php

namespace App\Modules\Portal\Http\Middleware;

use App\Modules\Portal\Support\Portal;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Portal host'unda KÖK (`/`) isteğini portal ana ekranına yönlendirir.
 *
 * Neden middleware? routes/web.php'deki `/` rotası (domain kısıtı YOK) portal
 * host'unda da eşleşir ve panele (HomeScreen) yönlendirirdi. Bu middleware,
 * o kapanış çalışmadan ÖNCE devreye girip portal host'unun kökünü `/mesaim`e
 * taşır. Panel host'unun `/` davranışı DEĞİŞMEZ (no-op).
 *
 * Global `web` yığınına eklidir; portal host DIŞINDA ve kök DIŞINDA hiçbir şey
 * yapmaz (tek dize karşılaştırması — ihmal edilebilir maliyet).
 */
class HandlePortalHost
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->isMethod('GET')
            && $request->path() === '/'
            && Portal::isPortalHost($request)) {
            return redirect('/mesaim');
        }

        return $next($request);
    }
}
