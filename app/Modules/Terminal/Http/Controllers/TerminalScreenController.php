<?php

namespace App\Modules\Terminal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Devices\Services\DeviceBindingService;
use App\Modules\Settings\Support\Features;
use App\Modules\Tenancy\TenantContext;
use App\Modules\Terminal\Models\TerminalDevice;
use App\Modules\Terminal\Services\TerminalTokenResolver;
use App\Modules\Terminal\Support\TerminalStation;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cookie;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Terminal giriş yüzeyi: GET /terminal/{token}
 *
 * Kimlik YALNIZ opak cihaz token'ıdır (ADR-008 deseni). Geçerli token →
 * cihaza bağlı GİZLİ terminal kullanıcısı Auth::login ile oturuma konur ve
 * istasyon ekranına yönlenir (KİLİTLİ mod). Rota "web" grubundadır (oturum
 * gerekir) ama terminal kullanıcısı normal login yapamaz — tek giriş kapısı
 * budur. Kilitli/rotasyonlu/geçersiz token uygun ekranı gösterir (kiosk
 * deseni). Cihaz sabit bir tablet olduğundan oturum kalıcıdır; kilit rozeti
 * + rota koruması ekranı istasyon dışına çıkarmaz.
 */
class TerminalScreenController extends Controller
{
    public function __construct(private readonly TerminalTokenResolver $resolver)
    {
    }

    public function show(Request $request, string $token): Response|RedirectResponse
    {
        // Tarama girişimine karşı emniyet supabı (terminal tek cihazdır; cömert).
        $limiterKey = 'terminal-screen:'.sha1((string) $request->ip());

        if (RateLimiter::tooManyAttempts($limiterKey, 60)) {
            return response()->view('terminal.error', ['kind' => 'throttled'], 429)
                ->header('Retry-After', (string) RateLimiter::availableIn($limiterKey));
        }

        RateLimiter::hit($limiterKey, 60);

        $res = $this->resolver->resolve($token);

        if ($res['status'] === 'revoked' || $res['status'] === 'inactive') {
            return response()->view('terminal.error', ['kind' => $res['status']], 410);
        }

        if ($res['status'] === 'invalid') {
            return response()->view('terminal.error', ['kind' => 'invalid'], 404);
        }

        $device = $res['device'];
        $tenant = $res['tenant'];

        $this->resolver->touch($device, $request->ip());

        if ($res['status'] === 'locked') {
            // Kilit ekranı kendini yoklar; panelden açılınca terminal canlanır.
            // Kilitliyken oturumu da düşür (varsa) — ekran dışına sızmasın.
            if (Auth::check() && Auth::user()?->is_terminal) {
                Auth::guard('web')->logout();
                $request->session()->invalidate();
                $request->session()->regenerateToken();
            }

            return $this->renderLocked($device->name, $tenant->name);
        }

        $user = $device->user;

        // Cihazın gizli kullanıcısı yoksa/bozulmuşsa: dürüstçe geçersiz say.
        if ($user === null || ! $user->is_terminal || ! $user->is_active) {
            return response()->view('terminal.error', ['kind' => 'invalid'], 404);
        }

        // ---- Cihaz kilidi (feature: device_lock; VARSAYILAN KAPALI) ----
        // Bu terminal token'ını İLK açan fiziksel cihaza kilitle; aynı token'la
        // FARKLI bir cihazdan gelen istek reddedilir ("başka cihaza kilitli").
        // Kilit yönetimi (boşa düşür / aktar / izni kaldır) → "İzinli Cihazlar"
        // ekranı (A3). Kapalıyken tek satır bile çalışmaz → mevcut davranış birebir
        // korunur (token her cihazda açılır). AuthorizedDevice tenant-kapsamlı
        // olduğundan binding'i açıkça bu kiracının bağlamında çalıştırırız.
        $deviceCookie = null;
        if (Features::enabled((int) $tenant->getKey(), 'device_lock')) {
            app(TenantContext::class)->setTenant($tenant);

            $binding = app(DeviceBindingService::class);
            $presented = $request->cookie(DeviceBindingService::COOKIE_NAME);
            $result = $binding->authorize(
                'terminal',
                $token,
                $presented !== null ? (string) $presented : null,
            );

            if (! $result->allowed) {
                return response()->view('devices.locked', [
                    'message' => $result->reason === 'revoked'
                        ? 'Bu cihazın erişim izni yönetici tarafından kaldırıldı.'
                        : 'Bu terminal bağlantısı başka bir cihaza kilitli. Yeni cihaza taşımak için yöneticiden "İzinli Cihazlar → Boşa düşür / Başka cihaza aktar" işlemini isteyin.',
                ], 403);
            }

            if ($result->tokenToPersist !== null) {
                $deviceCookie = Cookie::make(
                    name: DeviceBindingService::COOKIE_NAME,
                    value: $result->tokenToPersist,
                    minutes: 60 * 24 * 365 * 3, // ~3 yıl: fiziksel cihaz kalıcı kabul edilir
                    path: '/',
                    domain: null,
                    secure: $request->isSecure(),
                    httpOnly: true,
                    raw: false,
                    sameSite: 'lax',
                );
            }
        }

        // Oturumu terminal kullanıcısına geçir (kilitli mod frontend'de devreye
        // girer: nav gizli + rota koruması + kilit rozeti).
        Auth::guard('web')->login($user);
        $request->session()->regenerate();

        $redirect = redirect()->to(TerminalStation::screenFor($device->station));

        if ($deviceCookie !== null) {
            $redirect->withCookie($deviceCookie);
        }

        return $redirect;
    }

    /**
     * Kalp atışı: istasyon ekranı açıkken periyodik (~45 sn) çağrılır ve cihazın
     * `last_seen_at`'ini tazeler → panel sağlık rozeti "Çevrimiçi" kalır. İstek
     * zaten terminal kullanıcısıyla oturumlu olduğundan cihaz token'sız,
     * `user_id`'den çözülür (token yeniden ifşa edilmez).
     */
    public function heartbeat(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user === null || ! $user->is_terminal) {
            return response()->json(['status' => 'not_terminal'], 200);
        }

        $device = TerminalDevice::withoutTenancy()->where('user_id', $user->id)->first();

        if ($device !== null) {
            if ($device->isLocked()) {
                return response()->json(['status' => 'locked'], 200);
            }
            $this->resolver->touch($device, $request->ip());
        }

        return response()->json(['status' => 'ok', 'server_time' => now()->toIso8601String()]);
    }

    /** Kilit/çıkış düğmesi: terminal oturumunu kapatır (cihazda personel değişimi). */
    public function logout(Request $request): RedirectResponse
    {
        $user = $request->user();

        if ($user !== null && $user->is_terminal) {
            Auth::guard('web')->logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();
        }

        return redirect()->to('/giris');
    }

    /**
     * ANINDA uzaktan kilit (BUG #3 düzeltmesi): `heartbeat()` yanıtında
     * `status:'locked'` görünce istemci (useTerminalHeartbeat) buraya tam
     * sayfa yönlendirir. Token istemciye asla tekrar ifşa edilmediğinden
     * (bkz. heartbeat() dokümantasyonu) bu uç token'sız, oturumdaki
     * `user_id`'den cihazı çözer — `show()`'daki kilit dalıyla BİREBİR aynı
     * davranışı (oturumu düşür + kendini-yokla `terminal.locked` sayfası)
     * token olmadan üretir. Cihaz artık kilitli DEĞİLSE (yarış durumu —
     * panelden az önce açıldı) kendi istasyon ekranına geri yönlendirir.
     */
    public function relock(Request $request): Response|RedirectResponse
    {
        $user = $request->user();

        if ($user === null || ! $user->is_terminal) {
            return redirect()->to('/giris');
        }

        $device = TerminalDevice::withoutTenancy()->where('user_id', $user->id)->first();

        if ($device === null || ! $device->isLocked()) {
            return redirect()->to(TerminalStation::screenFor($device?->station));
        }

        $tenant = $device->tenant;

        Auth::guard('web')->logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return $this->renderLocked($device->name, $tenant?->name ?? '');
    }

    /** `terminal.locked` sayfasını üretir (show() + relock() ortak dalı). */
    private function renderLocked(string $deviceName, string $tenantName): Response
    {
        return response()->view('terminal.locked', [
            'deviceName' => $deviceName,
            'tenantName' => $tenantName,
        ], 200);
    }
}
