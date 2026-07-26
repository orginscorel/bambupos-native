<?php

namespace App\Modules\Terminal\Http\Middleware;

use App\Modules\Identity\Models\User;
use App\Modules\Terminal\Support\TerminalStation;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * TERMINAL KİLİTLİ MOD — rota koruması (§13, Faz A).
 *
 * is_terminal kullanıcı YALNIZ kendi istasyon ekranını açabilir. Başka bir
 * panel sayfasına (GET /panel/*, / , /terminal olmayan) gitmeye çalışırsa
 * kendi ekranına REDIRECT edilir. API uçları (/api/v1/kds/* polling +
 * eylemler) DOKUNULMAZ — zaten izin + istasyon-kapsamıyla korunur; ekranın
 * çalışması için gereklidir. /terminal/* (giriş/çıkış) de serbest bırakılır.
 *
 * Böylece fiziksel cihazdaki personel tüm paneli/sistemi göremez; kaçış
 * kapısı (nav çekmecesi) frontend'de zaten gizlidir, bu katman sunucu
 * tarafında da zorlar (derin-link / elle URL denemesine karşı).
 */
class EnsureTerminalLocked
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user instanceof User || ! $user->is_terminal) {
            return $next($request);
        }

        // Yalnız GET sayfa gezinmelerini kısıtla; API/mutasyon uçlarına dokunma.
        if (! $request->isMethod('GET') || $request->expectsJson()) {
            return $next($request);
        }

        // Giriş/çıkış yüzeyi + statik/health serbest.
        if ($request->is('terminal', 'terminal/*', 'api/*', 'up')) {
            return $next($request);
        }

        $screen = TerminalStation::screenFor($user->terminal_station);
        $screenPath = ltrim($screen, '/');
        $path = $request->path();

        // Zaten kendi ekranındaysa geç.
        if ($path === $screenPath) {
            return $next($request);
        }

        // Sipariş-giriş terminali adisyon detayına gidebilmeli
        // (/panel/siparisler/{id}); KDS/kasa ekranları TEK sayfadır.
        if (TerminalStation::allowsSubpaths($user->terminal_station)
            && str_starts_with($path, $screenPath.'/')) {
            return $next($request);
        }

        // Aksi: kendi ekranına yönlendir.
        return redirect()->to($screen);
    }
}
