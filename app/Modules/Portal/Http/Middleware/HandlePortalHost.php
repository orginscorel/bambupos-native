<?php

namespace App\Modules\Portal\Http\Middleware;

use App\Modules\Portal\Support\Portal;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Portal host'unu KAPALI BİR BAHÇEYE çevirir.
 *
 * `personel.*` alt alan adı YALNIZ personel self-servis portalını sunar; QR
 * yönetim paneli (Siparişler/Masalar/Kasa/Mutfak…) burada ASLA açılmaz. Aynı
 * Laravel uygulaması iki host'a hizmet ettiği için, portal host'unda panele ait
 * her yol (kök `/` dâhil) buradan portala yönlendirilir.
 *
 * İzin verilen yollar (portal host'unda geçerli):
 *   - Portal sayfaları: /mesaim, /raporlarim, /profilim, /takvim, /gorevlerim
 *   - Portal JSON:      /api/v1/portal/*
 *   - Kimlik doğrulama: /giris, /giris/*, /parola-sifirla*, /api/v1/auth/*
 *   - Web push:         /api/v1/push/*   (portal bildirimleri)
 * Bunların DIŞINDAKİ her yol:
 *   - GET  → girişliyse /mesaim'e, misafirse /giris'e yönlenir.
 *   - GET olmayan → 404 (panele ait yazma uçları portal host'unda yok sayılır).
 *
 * Panel/qrmenu host'unda TAMAMEN no-op (tek host karşılaştırması).
 * Global `web` yığınına eklidir.
 */
class HandlePortalHost
{
    /**
     * Portal host'unda çalışmasına izin verilen yol desenleri.
     *
     * @var list<string>
     */
    private const ALLOWED = [
        'panelim',
        'mesaim',
        'teslimatlarim',
        'raporlarim',
        'profilim',
        'takvim',
        'gorevlerim',
        'giris',
        'giris/*',
        'parola-sifirla',
        'parola-sifirla/*',
        'api/v1/portal/*',
        'api/v1/auth/*',
        'api/v1/push/*',
        // Panel-içi bildirim zili (portal da kullanır): liste + okundu işaretle.
        'api/v1/notifications',
        'api/v1/notifications/*',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        // Panel/qrmenu host: hiçbir şey yapma (izolasyon — davranış DEĞİŞMEZ).
        if (! Portal::isPortalHost($request)) {
            return $next($request);
        }

        // Portal host: izinli yol → geç.
        if ($request->is(...self::ALLOWED)) {
            return $next($request);
        }

        // İzinsiz yol (kök `/` dâhil): panele düşmesin, portala taşı.
        if ($request->isMethod('GET')) {
            return redirect($request->user() ? '/panelim' : '/giris');
        }

        // Portal host'unda tanımlı olmayan yazma ucu: yok say.
        abort(404);
    }
}
