<?php

namespace App\Modules\Kiosk\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kiosk\Services\KioskMenuBuilder;
use App\Modules\Kiosk\Services\KioskTokenResolver;
use App\Modules\Kiosk\Support\KioskFeature;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Kiosk tam ekran yüzeyi: GET /kiosk/{token}
 *
 * - Kimlik YALNIZ opak cihaz token'ı (ADR-008 deseni); oturum/çerez YOK —
 *   rota "web" grubunun DIŞINDA kayıtlıdır, yanıtta Set-Cookie olmaz.
 *   Sepet ve müşteri bilgisi tamamen istemci belleğindedir; sıfırlama =
 *   tam sayfa yeniden yükleme → önceki müşteriden hiçbir iz kalmaz (§18).
 * - Kilitli cihaz kilit ekranı görür (meta-refresh ile kendini yoklar).
 * - Rotasyonlanmış token 410 + açıklama; geçersiz token 404.
 */
class KioskScreenController extends Controller
{
    public function __construct(
        private readonly KioskTokenResolver $resolver,
        private readonly KioskMenuBuilder $menu,
    ) {
    }

    public function show(Request $request, string $token): Response
    {
        // Tarama girişimine karşı emniyet supabı (kiosk tek cihazdır; cömert).
        $limiterKey = 'kiosk-screen:'.sha1((string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 60)) {
            return response()->view('kiosk.error', ['kind' => 'throttled'], 429)
                ->header('Retry-After', (string) RateLimiter::availableIn($limiterKey))
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        RateLimiter::hit($limiterKey, 60);

        $res = $this->resolver->resolve($token);

        if ($res['status'] === 'revoked' || $res['status'] === 'inactive') {
            return response()->view('kiosk.error', ['kind' => $res['status']], 410)
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        if ($res['status'] === 'invalid') {
            return response()->view('kiosk.error', ['kind' => 'invalid'], 404)
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        $device = $res['device'];
        $tenant = $res['tenant'];
        $branch = $res['branch'];

        // Feature-flag kapısı (§9): kiosk özelliği işletme için kapalıysa
        // yüzey hiç yok sayılır (kapalı=yok). Yer tutucu şimdilik hep açık.
        if (! KioskFeature::enabled((int) $device->tenant_id)) {
            return response()->view('kiosk.error', ['kind' => 'invalid'], 404)
                ->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        $this->resolver->touch($device, $request->ip());

        if ($res['status'] === 'locked') {
            // Kilit ekranı kendini yoklar; panelden açılınca kiosk canlanır.
            return response()->view('kiosk.locked', [
                'deviceName' => $device->name,
                'tenantName' => $tenant->name,
            ], 200)->header('X-LiteSpeed-Cache-Control', 'no-cache');
        }

        $menu = $this->menu->build(
            (int) $tenant->getKey(),
            (int) $branch->getKey(),
            (string) ($branch->timezone ?: config('app.timezone')),
        );

        // Masada servis için masa listesi (yalnız bu cihazın şubesi).
        $tables = DB::table('tables')
            ->where('tenant_id', $tenant->getKey())
            ->where('branch_id', $branch->getKey())
            ->where('is_active', true)
            ->orderBy('number')->orderBy('name')
            ->limit(300)
            ->get(['id', 'name', 'number'])
            ->map(fn ($t) => [
                'id' => (int) $t->id,
                'label' => trim((string) $t->name.($t->number !== null ? ' · '.$t->number : '')),
            ])->values()->all();

        return response()->view('kiosk.screen', [
            'tenantName' => $tenant->name,
            'branchName' => $branch->name,
            'deviceName' => $device->name,
            'payload' => [
                'token' => $device->token,
                'tenant' => $tenant->name,
                'branch' => $branch->name,
                'device' => $device->name,
                'payment_mode' => $device->payment_mode,
                'currency' => '₺',
                'tables' => $tables,
                'menu' => $menu,
                'timing' => [
                    'idle' => (int) config('kiosk.idle_seconds', 90),
                    'warn' => (int) config('kiosk.warn_seconds', 20),
                    'receipt' => (int) config('kiosk.receipt_seconds', 45),
                    'heartbeat' => (int) config('kiosk.heartbeat_seconds', 45),
                    'poll' => (int) config('kiosk.payment_poll_seconds', 5),
                    'poll_max' => (int) config('kiosk.payment_poll_max', 12),
                ],
                'endpoints' => [
                    'order' => '/kiosk/api/orders',
                    'payment_query' => '/kiosk/api/payments/query',
                    'heartbeat' => '/kiosk/api/heartbeat',
                ],
            ],
        ])->header('X-LiteSpeed-Cache-Control', 'no-cache');
    }
}
