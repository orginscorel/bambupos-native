<?php

namespace App\Modules\Marketing\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Marketing\Models\DemoRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

/**
 * BamBumPOS pazarlama (kurumsal tanıtım) sitesi.
 *  - home(): premium landing (public ana sayfa). Oturum varsa panele yönlenir.
 *  - storeDemo(): "Demo İste" formu → lead kaydı (süper-admin işler). Hız sınırlı.
 */
class MarketingController extends Controller
{
    public function home(Request $request)
    {
        // Oturumlu kullanıcı → doğrudan uygulamaya (kendi açılış ekranı).
        $user = auth('web')->user();
        if ($user instanceof \App\Modules\Identity\Models\User) {
            return redirect(\App\Modules\Identity\Support\HomeScreen::resolve($user));
        }

        // Kurumsal tanıtım (landing) YALNIZ belirlenen tanıtım host'unda gösterilir
        // (ör. bambumpos.com apex + www). Diğer TÜM host'larda — qrmenu.*,
        // bogahostdeveloper.* vb. — kök doğrudan uygulama girişine (/giris) yönlenir.
        // MARKETING_HOST boşsa hiçbir host'ta landing çıkmaz (uygulama gibi davranır).
        $mkHost = trim((string) config('marketing.host', ''));
        $host = $request->getHost();
        $isMarketingHost = $mkHost !== '' && ($host === $mkHost || $host === 'www.'.$mkHost);

        if (! $isMarketingHost) {
            return redirect()->route('login');
        }

        return view('marketing.home');
    }

    public function storeDemo(Request $request): JsonResponse
    {
        // Hız sınırı: IP başına dakikada 3 talep (spam/abuse önleme).
        $key = 'demo-req:'.sha1((string) $request->ip());
        if (RateLimiter::tooManyAttempts($key, 3)) {
            return response()->json([
                'message' => 'Çok sık gönderdiniz. Lütfen biraz sonra tekrar deneyin.',
            ], 429)->header('Retry-After', (string) RateLimiter::availableIn($key));
        }
        RateLimiter::hit($key, 60);

        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:120'],
            'business' => ['nullable', 'string', 'max:160'],
            'phone' => ['required', 'string', 'min:7', 'max:40'],
            'email' => ['nullable', 'email', 'max:160'],
            'sector' => ['nullable', 'string', 'max:60'],
            'message' => ['nullable', 'string', 'max:1000'],
        ]);

        DemoRequest::create($data + [
            'status' => 'new',
            'source' => 'landing',
            'ip' => $request->ip(),
            'user_agent' => substr((string) $request->userAgent(), 0, 255),
        ]);

        return response()->json([
            'ok' => true,
            'message' => 'Talebiniz alındı! Ekibimiz en kısa sürede sizinle iletişime geçecek.',
        ], 201);
    }
}
