<?php

namespace App\Modules\Devices\Http\Middleware;

use App\Modules\Devices\Services\DeviceBindingService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cookie;
use Symfony\Component\HttpFoundation\Response;

/**
 * Cihaz kilidi kapısı (A3 — KULLANIMA HAZIR, HENÜZ HİÇBİR ROTAYA BAĞLI DEĞİL).
 *
 * KULLANIM: Route::middleware(['web', 'auth:web', 'tenant', 'device:kds'])
 * gibi 'tenant' middleware'inden SONRA eklenir (TenantContext'in çözülmüş
 * olması gerekir). İkinci parametre ile route parametresi adı verilebilir:
 *   'device:kiosk,token'  → linkKey = route('token') değeri (opak cihaz token'ı)
 *   'device:kds'          → linkKey = route adı (örn. panel.kds.kitchen) — bu
 *                            ekranlarda URL'de zaten benzersiz bir token yok.
 *
 * Sunulan token şu sırayla aranır: (1) ?dt= sorgu parametresi (ön-yetkili
 * paylaşım linki — YALNIZ ilk bağlanmada anlamlı), (2) qm_device_token çerezi,
 * (3) X-Device-Token header'ı (localStorage tabanlı istemciler için).
 *
 * Reddedilirse: JSON bekleyen istekte 403 JSON; aksi halde basit bir kilit
 * sayfası (resources/views/devices/locked.blade.php) render edilir.
 *
 * BİLİNÇLİ OLARAK KDS/kiosk/terminal route dosyalarına henüz EKLENMEDİ —
 * bkz. görev raporu: hangi route'lara nasıl uygulanacağı orada anlatılıyor
 * (özellikle kiosk'un public ekranı ADR-008/§18 gereği çerezsiz tasarlandığı
 * için bu middleware'in kiosk PUBLIC ekranına uygulanması ayrı bir karar
 * gerektirir).
 */
class EnsureDeviceAuthorized
{
    public function __construct(private readonly DeviceBindingService $binding)
    {
    }

    public function handle(Request $request, Closure $next, string $kind, ?string $routeParam = null): Response
    {
        $linkKey = $routeParam !== null
            ? (string) $request->route()?->parameter($routeParam)
            : (string) ($request->route()?->getName() ?? $request->path());

        $presentedToken = $request->query(DeviceBindingService::CLAIM_QUERY_PARAM)
            ?? $request->cookie(DeviceBindingService::COOKIE_NAME)
            ?? $request->header('X-Device-Token');

        $result = $this->binding->authorize($kind, $linkKey, $presentedToken !== null ? (string) $presentedToken : null);

        if (! $result->allowed) {
            return $this->deny($request, $result->reason ?? 'locked_to_other_device');
        }

        $response = $next($request);

        if ($result->tokenToPersist !== null) {
            $response->headers->setCookie(
                Cookie::make(
                    name: DeviceBindingService::COOKIE_NAME,
                    value: $result->tokenToPersist,
                    minutes: 60 * 24 * 365 * 3, // ~3 yıl: fiziksel cihaz kalıcı kabul edilir
                    path: '/',
                    domain: null,
                    secure: $request->isSecure(),
                    httpOnly: true,
                    raw: false,
                    sameSite: 'lax',
                ),
            );
        }

        return $response;
    }

    private function deny(Request $request, string $reason): Response
    {
        $messages = [
            'revoked' => 'Bu cihazın erişim izni yönetici tarafından kaldırıldı.',
            'locked_to_other_device' => 'Bu bağlantı başka bir cihaza kilitli.',
            'invalid_token' => 'Cihaz kimliği doğrulanamadı.',
        ];
        $message = $messages[$reason] ?? $messages['locked_to_other_device'];

        if ($request->expectsJson() || $request->is('api/*')) {
            return response()->json(['message' => $message, 'reason' => $reason], 403);
        }

        return response()->view('devices.locked', [
            'message' => $message,
        ], 403);
    }
}
