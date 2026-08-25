<?php

namespace App\Modules\Billing\Payments\Contracts;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Payments\Support\SaasCallbackResult;
use Illuminate\Http\Request;

/**
 * SaaS abonelik ÖDEME GEÇİDİ adapter sözleşmesi. app/Modules/Payments/Contracts/
 * PaymentProviderInterface (POS/kasa) ile AYNI DESEN, ayrı sözleşme — SaaS
 * abonelik faturası tahsilatı POS ödemesinden bambaşka bir akıştır (hosted
 * checkout/ödeme linki, kart bilgisi bize hiç gelmez).
 *
 * KRİTİK KURAL: checkoutUrl()'ün dönmüş olması tahsilatın gerçekleştiği
 * anlamına GELMEZ — kesin onay yalnız verifyCallback() ile doğrulanmış
 * sağlayıcı webhook'undan gelir (bkz. SaasPaymentService::handleCallback).
 */
interface SaasPaymentProvider
{
    /** Sağlayıcı anahtarı (config('saas_payment.provider') ile eşleşir). */
    public function key(): string;

    /**
     * Fatura için hosted ödeme sayfası URL'i üretir (tenant bu adrese
     * yönlendirilir). Sağlayıcı yapılandırılmamışsa (boş anahtar/manuel mod)
     * RuntimeException fırlatır — sahte/placeholder URL ÜRETMEZ.
     */
    public function checkoutUrl(SaasInvoice $invoice): string;

    /**
     * Callback/webhook isteğinin İMZASINI doğrular; ham istekten güvenilir
     * alanları çıkarır. Tutar KARŞILAŞTIRMASI SaasPaymentService'te yapılır
     * (tutar asla callback'ten "gerçek" kabul edilmez).
     */
    public function verifyCallback(Request $request): SaasCallbackResult;

    /**
     * Bazı sağlayıcılar (PayTR) webhook yanıtının TAM OLARAK düz metin
     * "OK" olmasını zorunlu kılar (aksi halde 24 saat tekrar dener); JSON
     * kabul edenler (iyzico) için false. Kontrolcü bu bayrağa göre yanıt
     * biçimini seçer — sağlayıcıya özgü davranış adaptöre gömülüdür.
     */
    public function expectsPlainTextResponse(): bool;
}
