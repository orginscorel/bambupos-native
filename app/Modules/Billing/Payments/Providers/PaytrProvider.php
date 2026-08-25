<?php

namespace App\Modules\Billing\Payments\Providers;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Payments\Contracts\SaasPaymentProvider;
use App\Modules\Billing\Payments\Support\SaasCallbackResult;
use App\Modules\Identity\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * PayTR iFrame API adaptörü (get-token → guvenli ödeme sayfası).
 * `merchant_oid` DAİMA "SI{invoice->id}" biçimindedir (alnum-only zorunluluğu
 * PayTR tarafından dayatılır) — webhook'ta invoiceRef bu kalıptan geri
 * çözülür.
 *
 * DOĞRULANMIŞ (kaynak: PayTR resmi entegrasyon dokümanı, yaygın/stabil,
 * yıllardır değişmemiş formüller):
 *  - get-token istek imzası: paytr_token =
 *    base64(hmac_sha256(merchant_id.user_ip.merchant_oid.email.payment_amount
 *    .user_basket.no_installment.max_installment.currency.test_mode
 *    .merchant_salt, merchant_key, raw))
 *  - Bildirim (webhook) imzası: hash =
 *    base64(hmac_sha256(merchant_oid.merchant_salt.status.total_amount,
 *    merchant_key, raw)) — `hash_equals` ile karşılaştırılır.
 *  - Bildirime yanıt DAİMA düz metin "OK" olmalı (imza geçerliyse; imza
 *    geçersizse "OK" YAZILMAZ — aksi halde PayTR sahte bildirimi de kabul
 *    edilmiş sayar). "OK" yazılmazsa PayTR ~24 saat boyunca tekrar dener.
 *
 * VARSAYIM/DOĞRULANMAMIŞ NOKTALAR (canlıya almadan önce PayTR mağaza
 * panelinden teyit edilmeli — bkz. rapor):
 *  - get-token uç noktası ve tam JSON/form alan adları (bilinen adres:
 *    https://www.paytr.com/odeme/api/get-token) — resmi PHP örnek koduyla
 *    birebir karşılaştırılmalı.
 *  - `email`/`user_name`/`user_address`/`user_phone` alanları Tenant'ta
 *    KYC verisi olmadığı için yaklaşık/placeholder değerlerle dolduruluyor.
 */
class PaytrProvider implements SaasPaymentProvider
{
    public function key(): string
    {
        return 'paytr';
    }

    private function configured(): bool
    {
        return (string) config('saas_payment.paytr.merchant_id', '') !== ''
            && (string) config('saas_payment.paytr.merchant_key', '') !== ''
            && (string) config('saas_payment.paytr.merchant_salt', '') !== '';
    }

    public function checkoutUrl(SaasInvoice $invoice): string
    {
        if (! $this->configured()) {
            throw new RuntimeException('PayTR yapılandırılmadı (PAYTR_MERCHANT_ID / _KEY / _SALT boş).');
        }

        $merchantId = (string) config('saas_payment.paytr.merchant_id');
        $merchantKey = (string) config('saas_payment.paytr.merchant_key');
        $merchantSalt = (string) config('saas_payment.paytr.merchant_salt');
        $testMode = (bool) config('saas_payment.paytr.test_mode', false) ? '1' : '0';

        $tenant = $invoice->tenant;
        $email = $this->resolveContactEmail((int) $invoice->tenant_id);
        $merchantOid = $this->merchantOid($invoice);
        $userIp = request()?->ip() ?: '127.0.0.1';
        $amountMinor = (int) $invoice->amount_minor; // PayTR payment_amount da kuruş bekler — birim aynı.
        $priceDecimal = number_format($amountMinor / 100, 2, '.', '');

        $userBasket = base64_encode(json_encode([
            ['BamBumPOS SaaS Abonelik — '.($invoice->number ?? ('#'.$invoice->id)), $priceDecimal, 1],
        ], JSON_UNESCAPED_UNICODE));

        $noInstallment = '1'; // abonelik tahsilatı — taksit yok
        $maxInstallment = '0';
        $currency = ($invoice->currency ?? 'TRY') === 'TRY' ? 'TL' : (string) $invoice->currency;

        $hashStr = $merchantId.$userIp.$merchantOid.$email.$amountMinor.$userBasket.$noInstallment.$maxInstallment.$currency.$testMode;
        $paytrToken = base64_encode(hash_hmac('sha256', $hashStr.$merchantSalt, $merchantKey, true));

        $form = [
            'merchant_id' => $merchantId,
            'user_ip' => $userIp,
            'merchant_oid' => $merchantOid,
            'email' => $email,
            'payment_amount' => $amountMinor,
            'user_basket' => $userBasket,
            'no_installment' => $noInstallment,
            'max_installment' => $maxInstallment,
            'currency' => $currency,
            'test_mode' => $testMode,
            'merchant_ok_url' => route('saas.pay.result', ['status' => 'ok']),
            'merchant_fail_url' => route('saas.pay.result', ['status' => 'fail']),
            'user_name' => $tenant?->name ?? 'BamBumPOS İşletmesi',
            'user_address' => 'Türkiye',
            'user_phone' => '05000000000',
            'timeout_limit' => '30',
            'debug_on' => '0',
            'paytr_token' => $paytrToken,
        ];

        try {
            $response = Http::asForm()->timeout(20)->post('https://www.paytr.com/odeme/api/get-token', $form);
        } catch (\Throwable $e) {
            throw new RuntimeException('PayTR bağlantı hatası: '.$e->getMessage(), previous: $e);
        }

        $json = (array) $response->json();

        if (($json['status'] ?? null) !== 'success' || empty($json['token'])) {
            Log::warning('saas_payment.paytr.checkout_failed', ['invoice_id' => $invoice->id, 'response' => $json]);

            throw new RuntimeException('PayTR ödeme token\'ı alınamadı: '.($json['reason'] ?? 'bilinmeyen hata'));
        }

        return 'https://www.paytr.com/odeme/guvenli/'.$json['token'];
    }

    public function verifyCallback(Request $request): SaasCallbackResult
    {
        $merchantKey = (string) config('saas_payment.paytr.merchant_key', '');
        $merchantSalt = (string) config('saas_payment.paytr.merchant_salt', '');

        if ($merchantKey === '' || $merchantSalt === '') {
            return new SaasCallbackResult(false, reason: 'PayTR yapılandırılmadı.');
        }

        $merchantOid = (string) $request->input('merchant_oid', '');
        $status = (string) $request->input('status', '');
        $totalAmount = (string) $request->input('total_amount', '');
        $hash = (string) $request->input('hash', '');

        if ($merchantOid === '' || $hash === '') {
            return new SaasCallbackResult(false, reason: 'merchant_oid/hash eksik.');
        }

        $expected = base64_encode(hash_hmac('sha256', $merchantOid.$merchantSalt.$status.$totalAmount, $merchantKey, true));

        if (! hash_equals($expected, $hash)) {
            return new SaasCallbackResult(false, reason: 'Hash doğrulanamadı (bkz. PayTR bildirim dokümanı).');
        }

        if (! preg_match('/^SI(\d+)$/', $merchantOid, $m)) {
            return new SaasCallbackResult(false, reason: 'merchant_oid beklenen kalıpta değil: '.$merchantOid);
        }

        return new SaasCallbackResult(
            valid: true,
            invoiceRef: $m[1],
            providerTxnId: $merchantOid,
            status: $status === 'success' ? 'approved' : 'declined',
            amountMinor: $totalAmount !== '' ? (int) $totalAmount : null,
        );
    }

    public function expectsPlainTextResponse(): bool
    {
        return true;
    }

    private function merchantOid(SaasInvoice $invoice): string
    {
        return 'SI'.$invoice->id;
    }

    /** Bkz. IyzicoProvider::resolveContactEmail — aynı varsayım. */
    private function resolveContactEmail(int $tenantId): string
    {
        $email = User::query()->where('tenant_id', $tenantId)->orderBy('id')->value('email');

        return $email !== null && $email !== '' ? $email : (string) config('site.contact.support_email', 'destek@bambumpos.com');
    }
}
