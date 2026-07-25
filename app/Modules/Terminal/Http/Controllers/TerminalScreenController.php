<?php

namespace App\Modules\Terminal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Terminal\Services\TerminalTokenResolver;
use App\Modules\Terminal\Support\TerminalStation;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
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

            return response()->view('terminal.locked', [
                'deviceName' => $device->name,
                'tenantName' => $tenant->name,
            ], 200);
        }

        $user = $device->user;

        // Cihazın gizli kullanıcısı yoksa/bozulmuşsa: dürüstçe geçersiz say.
        if ($user === null || ! $user->is_terminal || ! $user->is_active) {
            return response()->view('terminal.error', ['kind' => 'invalid'], 404);
        }

        // Oturumu terminal kullanıcısına geçir (kilitli mod frontend'de devreye
        // girer: nav gizli + rota koruması + kilit rozeti).
        Auth::guard('web')->login($user);
        $request->session()->regenerate();

        return redirect()->to(TerminalStation::screenFor($device->station));
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
}
