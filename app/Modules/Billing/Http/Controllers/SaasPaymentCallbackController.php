<?php

namespace App\Modules\Billing\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Billing\Payments\SaasPaymentRegistry;
use App\Modules\Billing\Services\SaasPaymentService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;

/**
 * SaaS ödeme sağlayıcı webhook/bildirim ucu — OTURUMSUZ, CSRF DIŞI
 * (routes/saas_payment.php'de "web" grubunun DIŞINDA kaydedilir; PaymentCallbackController
 * ile AYNI desen, bkz. app/Modules/Payments/Http/Controllers/PaymentCallbackController.php).
 *
 * Kimlik = sağlayıcı İMZASI (provider->verifyCallback). Yanıt BİÇİMİ
 * sağlayıcıya göre değişir: PayTR düz metin "OK" bekler (aksi halde ~24 saat
 * tekrar dener), iyzico JSON kabul eder — bu ayrım adaptördeki
 * expectsPlainTextResponse() bayrağından okunur (kod DEĞİL, adaptör karar
 * verir).
 */
class SaasPaymentCallbackController extends Controller
{
    public function __construct(
        private readonly SaasPaymentService $payments,
        private readonly SaasPaymentRegistry $registry,
    ) {
    }

    public function handle(Request $request, string $provider): Response
    {
        $result = $this->payments->handleCallback($provider, $request);
        $plainText = $this->registry->has($provider) && $this->registry->get($provider)->expectsPlainTextResponse();

        if (! $result['ok']) {
            Log::warning('saas_payment.callback_rejected', [
                'provider' => $provider,
                'message' => $result['message'],
                'ip' => $request->ip(),
            ]);

            // Sağlayıcıya iç detay sızdırılmaz; işlem kimliği loglarda.
            return $plainText
                ? response('FAIL', 400)
                : response()->json(['status' => 'rejected'], 400);
        }

        return $plainText
            ? response('OK')
            : response()->json(['status' => 'ok']);
    }
}
