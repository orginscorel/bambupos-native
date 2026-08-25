<?php

namespace App\Modules\Billing\Payments\Providers;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Payments\Contracts\SaasPaymentProvider;
use App\Modules\Billing\Payments\Support\SaasCallbackResult;
use App\Modules\Identity\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * iyzico Checkout Form (HPP — Hosted Payment Page) adaptörü. iyzico'nun
 * KENDİ "Abonelik" (Subscription) ürünü BİLİNÇLİ OLARAK KULLANILMIYOR —
 * abonelik/dönem/fatura döngüsünün TEK sahibi bizim BillingService'imizdir
 * (nextPeriodEnd, markPaid); iyzico burada yalnız TEK BİR faturanın
 * tahsilatı için hosted ödeme sayfası üreten bir ödeme yöntemidir.
 *
 * Akış: checkoutUrl() → POST /payment/iyzipos/checkoutform/initialize/auth/ecom
 * (kimlik: IYZWSv2 HMACSHA256, aşağıda) → dönen `paymentPageUrl`'e yönlendir.
 * Sonuç YALNIZ imzalı webhook (X-IYZ-SIGNATURE-V3) ile kesinleşir.
 *
 * VARSAYIM/DOĞRULANMAMIŞ NOKTALAR (canlıya almadan önce iyzico güncel
 * dokümanıyla teyit edilmeli — bkz. rapor):
 *  - Checkout Form Initialize isteğinin `buyer`/`billingAddress`/`basketItems`
 *    ZORUNLU alanları burada Tenant'tan üretilebilen asgari/placeholder
 *    verilerle dolduruluyor (Tenant modelinde adres/TCKN gibi KYC alanları
 *    YOK). Gerçek kullanımda bu alanlar işletme onboarding formundan
 *    toplanmalı.
 *  - IYZWSv2 imza şeması (randomKey+uriPath+requestBody → HMAC-SHA256 hex,
 *    "apiKey:...&randomKey:...&signature:..." base64) resmi dokümandan
 *    alınmıştır (docs.iyzico.com/en/getting-started/preliminaries/
 *    authentication/hmacsha256-auth) — API sürümüyle değişebilir.
 *  - Webhook alan adları/imza formülü (HPP: secretKey+iyziEventType+
 *    iyziPaymentId+token+paymentConversationId+status → HMAC-SHA256 hex)
 *    resmi dokümandan alınmıştır (docs.iyzico.com/en/advanced/webhook) —
 *    `status` alanının tam değer kümesi ("SUCCESS"/"FAILURE" vb.) sandbox'ta
 *    doğrulanmalı.
 */
class IyzicoProvider implements SaasPaymentProvider
{
    public function key(): string
    {
        return 'iyzico';
    }

    private function configured(): bool
    {
        return (string) config('saas_payment.iyzico.api_key', '') !== ''
            && (string) config('saas_payment.iyzico.secret', '') !== '';
    }

    public function checkoutUrl(SaasInvoice $invoice): string
    {
        if (! $this->configured()) {
            throw new RuntimeException('iyzico yapılandırılmadı (IYZICO_API_KEY / IYZICO_SECRET boş).');
        }

        $tenant = $invoice->tenant;
        $contactEmail = $this->resolveContactEmail((int) $invoice->tenant_id);
        $conversationId = (string) $invoice->id; // webhook'ta invoiceRef eşlemesi bu alandan yapılır
        $priceDecimal = number_format(((int) $invoice->amount_minor) / 100, 2, '.', '');

        // NOT (varsayım — yukarıdaki docblock): iyzico buyer/adres alanlarını
        // ZORUNLU kılar; Tenant'ta bu KYC verisi henüz toplanmıyor, bu yüzden
        // makul placeholder'larla dolduruluyor. Canlıya geçişte gerçek veriyle
        // değiştirilmeli (ör. Tenant'a fatura adresi alanları eklenerek).
        $buyerName = $tenant?->name ?? 'BamBumPOS';
        [$buyerFirst, $buyerLast] = $this->splitName($buyerName);

        $body = [
            'locale' => 'tr',
            'conversationId' => $conversationId,
            'price' => $priceDecimal,
            'paidPrice' => $priceDecimal,
            'currency' => $invoice->currency ?? 'TRY',
            'basketId' => 'SAAS-INV-'.$invoice->id,
            'paymentGroup' => 'PRODUCT',
            // NOT: bu alan iyzico'nun tarayıcıyı geri YÖNLENDİRDİĞİ adrestir
            // (klasik checkout-form akışı); ASENKRON imzalı webhook
            // (X-IYZ-SIGNATURE-V3, verifyCallback() burada doğrular) AYRICA
            // iyzico Merchant Panel'de "Webhook URL" olarak bu AYNI adrese
            // kayıtlı OLMALIDIR — API isteğindeki bu alan onu OTOMATİK
            // ayarlamaz (TODO(entegrasyon): panelden teyit et).
            'callbackUrl' => route('saas.payment.callback', ['provider' => 'iyzico']),
            'enabledInstallments' => [1],
            'buyer' => [
                'id' => 'TENANT-'.$invoice->tenant_id,
                'name' => $buyerFirst,
                'surname' => $buyerLast,
                'gsmNumber' => '+905000000000',
                'email' => $contactEmail,
                'identityNumber' => '11111111111', // TODO(entegrasyon): gerçek TCKN/VKN toplanmalı
                'registrationAddress' => 'Türkiye',
                'ip' => request()?->ip() ?? '127.0.0.1',
                'city' => 'İstanbul',
                'country' => 'Turkey',
            ],
            'shippingAddress' => [
                'contactName' => $buyerName,
                'city' => 'İstanbul',
                'country' => 'Turkey',
                'address' => 'Türkiye',
            ],
            'billingAddress' => [
                'contactName' => $buyerName,
                'city' => 'İstanbul',
                'country' => 'Turkey',
                'address' => 'Türkiye',
            ],
            'basketItems' => [[
                'id' => 'SAAS-PLAN-'.($invoice->subscription?->plan_key ?? 'abonelik'),
                'name' => 'BamBumPOS SaaS Abonelik — '.($invoice->number ?? ('#'.$invoice->id)),
                'category1' => 'SaaS',
                'itemType' => 'VIRTUAL',
                'price' => $priceDecimal,
            ]],
        ];

        $path = '/payment/iyzipos/checkoutform/initialize/auth/ecom';

        try {
            $response = $this->post($path, $body);
        } catch (\Throwable $e) {
            throw new RuntimeException('iyzico bağlantı hatası: '.$e->getMessage(), previous: $e);
        }

        if (($response['status'] ?? null) !== 'success' || empty($response['paymentPageUrl'])) {
            Log::warning('saas_payment.iyzico.checkout_failed', ['invoice_id' => $invoice->id, 'response' => $response]);

            throw new RuntimeException('iyzico ödeme sayfası oluşturulamadı: '.($response['errorMessage'] ?? 'bilinmeyen hata'));
        }

        return (string) $response['paymentPageUrl'];
    }

    public function verifyCallback(Request $request): SaasCallbackResult
    {
        $secret = (string) config('saas_payment.iyzico.secret', '');

        if ($secret === '') {
            return new SaasCallbackResult(false, reason: 'iyzico secret yapılandırılmadı.');
        }

        $signatureHeader = (string) $request->header('X-IYZ-SIGNATURE-V3', '');

        if ($signatureHeader === '') {
            return new SaasCallbackResult(false, reason: 'X-IYZ-SIGNATURE-V3 başlığı eksik.');
        }

        // HPP (Checkout Form) webhook alanları — docs.iyzico.com/en/advanced/webhook.
        $eventType = (string) $request->input('iyziEventType', '');
        $paymentId = (string) $request->input('iyziPaymentId', '');
        $token = (string) $request->input('token', '');
        $conversationId = (string) $request->input('paymentConversationId', '');
        $status = (string) $request->input('status', '');

        if ($eventType === '' || $conversationId === '') {
            return new SaasCallbackResult(false, reason: 'Zorunlu webhook alanları eksik.');
        }

        $message = $secret.$eventType.$paymentId.$token.$conversationId.$status;
        $expected = bin2hex(hash_hmac('sha256', $message, $secret, true));

        if (! hash_equals($expected, $signatureHeader)) {
            return new SaasCallbackResult(false, reason: 'İmza doğrulanamadı (X-IYZ-SIGNATURE-V3).');
        }

        // approved/declined durum eşlemesi VARSAYIMDIR (bkz. sınıf docblock'u) —
        // sandbox'ta gerçek `status` değeri teyit edilmeli.
        $mappedStatus = match (true) {
            in_array(strtoupper($status), ['SUCCESS', 'APPROVED', '1'], true) => 'approved',
            in_array(strtoupper($status), ['FAILURE', 'FAILED', 'DECLINED', '0'], true) => 'declined',
            default => null,
        };

        return new SaasCallbackResult(
            valid: true,
            invoiceRef: $conversationId,
            providerTxnId: $paymentId !== '' ? $paymentId : $token,
            status: $mappedStatus,
        );
    }

    public function expectsPlainTextResponse(): bool
    {
        return false;
    }

    /* =================== iç yardımcılar =================== */

    /**
     * IYZWSv2 kimlik doğrulama başlığı üretir.
     * payload = randomKey + uriPath + requestBodyJson
     * signature = HMAC-SHA256(payload, secretKey) → HEX
     * authorizationString = "apiKey:{apiKey}&randomKey:{randomKey}&signature:{signature}"
     * header = "IYZWSv2 " + base64(authorizationString)
     *
     * @param  array<string, mixed>  $body
     * @return array<string, mixed>
     */
    private function post(string $path, array $body): array
    {
        $apiKey = (string) config('saas_payment.iyzico.api_key', '');
        $secret = (string) config('saas_payment.iyzico.secret', '');
        $baseUrl = rtrim((string) config('saas_payment.iyzico.base_url', ''), '/');

        $randomKey = (string) (now()->getTimestampMs()).'-'.Str::random(8);
        $jsonBody = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $payload = $randomKey.$path.$jsonBody;
        $signature = hash_hmac('sha256', $payload, $secret);
        $authString = 'apiKey:'.$apiKey.'&randomKey:'.$randomKey.'&signature:'.$signature;
        $authorization = 'IYZWSv2 '.base64_encode($authString);

        $response = Http::withHeaders([
            'Authorization' => $authorization,
            'x-iyzi-rnd' => $randomKey,
            'Content-Type' => 'application/json',
        ])->timeout(20)->withBody($jsonBody, 'application/json')->post($baseUrl.$path);

        return (array) $response->json();
    }

    /** @return array{0: string, 1: string} */
    private function splitName(string $full): array
    {
        $parts = preg_split('/\s+/', trim($full), 2) ?: [$full];

        return [$parts[0] !== '' ? $parts[0] : 'BamBumPOS', $parts[1] ?? 'Abonelik'];
    }

    /**
     * Fatura sahibi işletmenin ilk (genelde kurucu/sahip) kullanıcısının
     * e-postası — Tenant modelinde ayrı bir "fatura e-postası" alanı YOK.
     * VARSAYIM: TenantProvisioner ile açılan işletmelerde ilk kullanıcı sahiptir.
     */
    private function resolveContactEmail(int $tenantId): string
    {
        $email = User::query()->where('tenant_id', $tenantId)->orderBy('id')->value('email');

        return $email !== null && $email !== '' ? $email : (string) config('site.contact.support_email', 'destek@bambumpos.com');
    }
}
