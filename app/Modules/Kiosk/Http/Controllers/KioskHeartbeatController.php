<?php

namespace App\Modules\Kiosk\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Devices\Services\DeviceBindingService;
use App\Modules\Kiosk\Services\KioskTokenResolver;
use App\Modules\Settings\Support\Features;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Kiosk kalp atışı: POST /kiosk/api/heartbeat {token, device_token?}
 *
 * - last_seen_at günceller (panel sağlık rozeti).
 * - Cihaz durumunu döner: kilitlendi/iptal edildiyse istemci ekranı yeniler
 *   ve sunucunun vereceği kilit/410 sayfasına düşer (uzaktan kilit anında).
 * - Cihaz kilidi (feature: device_lock; §18 uyumlu — çerez YOK): bu kiosk
 *   bağlantısını (token) İLK açan cihaz kilitlenir; farklı cihaz reddedilir.
 *   Cihaz kimliği istemcide localStorage'da tutulur (MÜŞTERİ VERİSİ DEĞİL);
 *   sunucu ilk bağlanmada üretip döner, istemci saklar ve her kalp atışında
 *   geri sunar. GET /kiosk/{token} sayfası cache'li/oturumsuz KALIR.
 */
class KioskHeartbeatController extends Controller
{
    public function __construct(private readonly KioskTokenResolver $resolver)
    {
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:64'],
            'device_token' => ['sometimes', 'nullable', 'string', 'max:64'],
        ]);

        $limiterKey = 'kiosk-heartbeat:'.sha1($data['token'].'|'.(string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 30)) {
            return response()->json(['message' => 'Çok sık istek.'], 429);
        }

        RateLimiter::hit($limiterKey, 60);

        $res = $this->resolver->resolve($data['token']);

        if ($res['status'] === 'revoked' || $res['status'] === 'inactive') {
            return response()->json(['status' => $res['status']], 410);
        }

        if ($res['status'] === 'invalid') {
            return response()->json(['status' => 'invalid'], 404);
        }

        $device = $res['device'];
        $this->resolver->touch($device, $request->ip());

        $extra = [];

        // ---- Cihaz kilidi (feature: device_lock; VARSAYILAN KAPALI) ----
        if (Features::enabled((int) $device->tenant_id, 'device_lock')) {
            app(TenantContext::class)->setTenant((int) $device->tenant_id);

            $result = app(DeviceBindingService::class)
                ->authorize('kiosk', $data['token'], $data['device_token'] ?? null);

            if (! $result->allowed) {
                return response()->json([
                    'status'  => 'locked_device',
                    'message' => $result->reason === 'revoked'
                        ? 'Bu cihazın erişim izni yönetici tarafından kaldırıldı.'
                        : 'Bu kiosk bağlantısı başka bir cihaza kilitli.',
                ])->header('X-LiteSpeed-Cache-Control', 'no-cache');
            }

            // İlk bağlanma → istemcinin saklaması için cihaz kimliğini döndür.
            if ($result->tokenToPersist !== null) {
                $extra['device_token'] = $result->tokenToPersist;
            }
        }

        return response()->json([
            'status' => $res['status'] === 'locked' ? 'locked' : 'ok',
            'server_time' => now()->toIso8601String(),
        ] + $extra)->header('X-LiteSpeed-Cache-Control', 'no-cache');
    }
}
