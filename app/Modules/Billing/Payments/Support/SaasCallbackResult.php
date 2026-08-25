<?php

namespace App\Modules\Billing\Payments\Support;

/**
 * SaasPaymentProvider::verifyCallback çıktısı. `valid=false` ise HİÇBİR
 * alanına güvenilmez (Payments\Providers\CallbackResult ile aynı mantık,
 * ADR-010 — ama SaaS abonelik faturası bağlamında).
 */
final class SaasCallbackResult
{
    public function __construct(
        public readonly bool $valid,
        public readonly ?string $invoiceRef = null,      // saas_invoices.id (string) — eşleme anahtarı
        public readonly ?string $providerTxnId = null,
        public readonly ?string $status = null,           // approved | declined
        public readonly ?int $amountMinor = null,         // sağlayıcının bildirdiği tutar (yalnız KARŞILAŞTIRMA)
        public readonly ?string $reason = null,            // geçersizlik/red nedeni (log için; sağlayıcıya sızdırılmaz)
    ) {
    }
}
