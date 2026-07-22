<?php

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use Illuminate\Http\Request;

/**
 * SANDBOX ADAPTER İSKELETİ — gerçek sağlayıcı entegrasyonunun kalıbı.
 *
 * BİLİNÇLİ OLARAK ÇALIŞMAZ: kimlik bilgileri yapılandırılmadan her çağrı
 * ERROR döner; hiçbir yerde "yapılmış gibi" başarı üretmez. Gerçek bir
 * sağlayıcıya (iyzico/PayTR/banka sanal POS/Ingenico-Verifone ECR)
 * bağlanmak için gerekenler modül README'sindedir
 * (app/Modules/Payments/README.md §"Gerçek sağlayıcı ekleme").
 *
 * Entegrasyonu yazacak kişi için işaretli TODO'lar aşağıdadır; sözleşme
 * kuralları (timeout'u başarısız sayma, tutarı callback'ten alma vb.)
 * MockPosProvider ve PaymentService'tekiyle birebir aynıdır.
 */
class SandboxPosProvider implements PaymentProviderInterface
{
    public function key(): string
    {
        return 'sandbox';
    }

    private function notConfigured(): ProviderResult
    {
        return new ProviderResult(
            ProviderResult::ERROR,
            null,
            'Sandbox sağlayıcı yapılandırılmadı (PAYMENTS_SANDBOX_* env). Gerçek entegrasyon adımları: app/Modules/Payments/README.md',
        );
    }

    private function configured(): bool
    {
        return (string) config('payments.sandbox.api_key', '') !== ''
            && (string) config('payments.sandbox.base_url', '') !== '';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): POST {base_url}/payments  body: {amount, currency,
        //   merchant_ref: $payment->reference, terminal: $payment->terminal_id}
        //   → sağlayıcı işlem kimliğini ProviderResult::providerTxnId'ye koy.
        return $this->notConfigured();
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): ECR/bulut-POS "push amount" çağrısı. HTTP timeout
        //   düşük tutulmalı (5-10 sn) ve TIMEOUT sonucu ASLA declined'a
        //   çevrilmemeli — PaymentService queryPayment ile netleştirir.
        return $this->notConfigured();
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): GET {base_url}/payments/{provider_txn_id} —
        //   sağlayıcı durumunu approved/declined/pending'e eşle.
        return $this->notConfigured();
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): void ucu. Gün kesimi geçtiyse sağlayıcı iade
        //   isteyebilir; DECLINED dönerse kasiyer iade akışına yönlendirilir.
        return $this->notConfigured();
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): kısmi iade desteğini sağlayıcı dokümanından
        //   doğrula; desteklenmiyorsa yalnız tam iade kabul et (DECLINED).
        return $this->notConfigured();
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        if (! $this->configured()) {
            return $this->notConfigured();
        }

        // TODO(entegrasyon): gün sonu (settlement) raporundan işlem eşleşmesi.
        return $this->notConfigured();
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        // TODO(entegrasyon): sağlayıcının İMZA ŞEMASINI uygula (ör. PayTR:
        //   base64(hmac_sha256(merchant_oid.salt.status.total_amount, key))).
        //   Kurallar: (1) hash_equals ile karşılaştır, (2) timestamp/nonce
        //   penceresi uygula, (3) tutarı SADECE karşılaştırma için çıkar.
        return new CallbackResult(false, reason: 'Sandbox sağlayıcı yapılandırılmadı.');
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        return new TerminalStatus(false, $terminalId, 'Sandbox sağlayıcı yapılandırılmadı.');
    }
}
