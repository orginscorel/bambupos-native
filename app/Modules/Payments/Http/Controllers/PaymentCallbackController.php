<?php

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Payments\Services\PaymentService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Sağlayıcı callback ucu (oturumsuz, CSRF dışı — "web" grubunda DEĞİL).
 *
 * Güvenlik: kimlik = sağlayıcı İMZASI (HMAC) + zaman damgası penceresi
 * (provider->verifyCallback). Tutar callback'ten alınmaz; kendi kaydımızla
 * karşılaştırılır, uyuşmazlık suspect+alarm (ADR-010). Replay: imza eski
 * timestamp'i reddeder; ayrıca settle yalnız Pending→Succeeded tek sefer
 * geçer — tekrar gelen callback 200 alır ama İKİNCİ kez işlemez.
 */
class PaymentCallbackController extends Controller
{
    public function __construct(private readonly PaymentService $payments)
    {
    }

    public function handle(Request $request, string $provider): JsonResponse
    {
        $result = $this->payments->handleCallback($provider, $request);

        if (! $result['ok']) {
            Log::warning('payments.callback_rejected', [
                'provider' => $provider,
                'message' => $result['message'],
                'ip' => $request->ip(),
            ]);

            // Sağlayıcıya iç detay sızdırılmaz; işlem kimliği loglarda.
            return response()->json(['status' => 'rejected'], 400);
        }

        return response()->json(['status' => 'ok']);
    }
}
