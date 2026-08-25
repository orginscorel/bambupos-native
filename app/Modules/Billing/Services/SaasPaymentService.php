<?php

namespace App\Modules\Billing\Services;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Payments\SaasPaymentRegistry;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * SaaS ödeme geçidi ORKESTRASYONU: hosted checkout URL üretimi + sağlayıcı
 * webhook/callback işlenmesi. BillingService'in (dönem/fatura veri modeli)
 * ÜSTÜNE oturur — para tahsilatının GERÇEK doğrulaması burada, dönem/durum
 * geçişi orada (markPaid) yapılır.
 *
 * İDEMPOTENCY: ayrı bir idempotency_keys tablosu KULLANILMAZ (bilinçli —
 * daha basit ve yeterli bir alternatif seçildi); bunun yerine
 * `saas_invoices.status` DB SATIR KİLİDİ (lockForUpdate) içinde bir
 * "guard" olarak kullanılır: aynı callback iki kez (hatta eşzamanlı)
 * gelirse, ikinci çağrı kilidi aldığında faturayı zaten 'paid' bulur ve
 * hiçbir şey değiştirmeden 'ok' döner (BillingService::markPaid'in kendi
 * isPaid() koruması da AYNI garantiyi ikinci bir katman olarak sağlar).
 */
class SaasPaymentService
{
    public function __construct(
        private readonly SaasPaymentRegistry $registry,
        private readonly BillingService $billing,
    ) {
    }

    /** Bir fatura için hosted ödeme sayfası URL'i (aktif sağlayıcı üzerinden). */
    public function checkoutUrlFor(SaasInvoice $invoice): string
    {
        if ($invoice->isPaid()) {
            throw new RuntimeException('Fatura zaten ödenmiş.');
        }

        if ($invoice->status === SaasInvoice::STATUS_VOID) {
            throw new RuntimeException('İptal edilmiş fatura için ödeme başlatılamaz.');
        }

        return $this->registry->current()->checkoutUrl($invoice);
    }

    /**
     * Sağlayıcı webhook/callback'ini işler. Dönüş: ['ok' => bool, 'message' => string, 'invoice' => ?SaasInvoice].
     * `ok=true` HTTP 200 (sağlayıcıya "aldım, tekrar deneme") anlamına gelir —
     * bu, tahsilatın BAŞARILI olduğu anlamına GELMEZ (ör. 'declined' de ok=true
     * döner: bildirim geçerliydi, yalnız ödeme reddedildi).
     *
     * @return array{ok: bool, message: string, invoice: ?SaasInvoice}
     */
    public function handleCallback(string $providerKey, Request $request): array
    {
        if (! $this->registry->has($providerKey)) {
            return ['ok' => false, 'message' => 'Bilinmeyen sağlayıcı.', 'invoice' => null];
        }

        $provider = $this->registry->get($providerKey);
        $result = $provider->verifyCallback($request);

        if (! $result->valid) {
            return ['ok' => false, 'message' => 'Doğrulama başarısız: '.($result->reason ?? 'imza'), 'invoice' => null];
        }

        if ($result->invoiceRef === null || ! ctype_digit($result->invoiceRef)) {
            return ['ok' => false, 'message' => 'Fatura referansı çözümlenemedi.', 'invoice' => null];
        }

        return DB::transaction(function () use ($result, $providerKey) {
            /** @var SaasInvoice|null $invoice */
            $invoice = SaasInvoice::query()->lockForUpdate()->find((int) $result->invoiceRef);

            if ($invoice === null) {
                return ['ok' => false, 'message' => 'Fatura bulunamadı: '.$result->invoiceRef, 'invoice' => null];
            }

            // Tutar karşılaştırması: sağlayıcı bir tutar bildirdiyse kendi
            // kaydımızla eşleşmeli — uyuşmazlıkta ONAYLANMAZ (suspect log).
            if ($result->amountMinor !== null && $result->amountMinor !== (int) $invoice->amount_minor) {
                Log::warning('saas_payment.amount_mismatch', [
                    'invoice_id' => $invoice->id,
                    'provider' => $providerKey,
                    'expected_minor' => (int) $invoice->amount_minor,
                    'reported_minor' => $result->amountMinor,
                ]);

                return ['ok' => false, 'message' => 'Tutar uyuşmazlığı.', 'invoice' => $invoice];
            }

            // İDEMPOTENT KORUMA: satır kilidi altında zaten ödenmişse hiçbir
            // şey değiştirmeden başarı dön (replay/çift-webhook güvenli).
            if ($invoice->isPaid()) {
                return ['ok' => true, 'message' => 'Zaten işlenmiş (idempotent).', 'invoice' => $invoice];
            }

            if ($result->status !== 'approved') {
                return ['ok' => true, 'message' => 'Bildirim geçerli; ödeme onaylanmadı ('.($result->status ?? 'bilinmiyor').').', 'invoice' => $invoice];
            }

            // Sağlayıcı izini faturaya kaydet (markPaid() aynı nesneyi save
            // edeceği için burada save() ÇAĞRILMAZ — tek transaction/tek yazım).
            $invoice->meta = array_merge((array) $invoice->meta, [
                'payment_provider' => $providerKey,
                'provider_txn_id' => $result->providerTxnId,
                'paid_via_callback_at' => now()->toIso8601String(),
            ]);

            $invoice = $this->billing->markPaid($invoice);

            $tenant = $invoice->tenant;
            if ($tenant && $tenant->isSuspended()) {
                $tenant->activate();
            }

            return ['ok' => true, 'message' => 'OK', 'invoice' => $invoice];
        });
    }
}
