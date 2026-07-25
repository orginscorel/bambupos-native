<?php

namespace App\Modules\Kiosk\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kiosk\Services\KioskTokenResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Kiosk kalp atışı: POST /kiosk/api/heartbeat {token}
 *
 * - last_seen_at günceller (panel sağlık rozeti).
 * - Cihaz durumunu döner: kilitlendi/iptal edildiyse istemci ekranı yeniler
 *   ve sunucunun vereceği kilit/410 sayfasına düşer (uzaktan kilit anında).
 */
class KioskHeartbeatController extends Controller
{
    public function __construct(private readonly KioskTokenResolver $resolver)
    {
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate(['token' => ['required', 'string', 'max:64']]);

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

        $this->resolver->touch($res['device'], $request->ip());

        return response()->json([
            'status' => $res['status'] === 'locked' ? 'locked' : 'ok',
            'server_time' => now()->toIso8601String(),
        ])->header('X-LiteSpeed-Cache-Control', 'no-cache');
    }
}
