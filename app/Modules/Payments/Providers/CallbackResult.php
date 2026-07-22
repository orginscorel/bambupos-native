<?php

namespace App\Modules\Payments\Providers;

/**
 * verifyCallback çıktısı. `valid=false` ise HİÇBİR alanına güvenilmez.
 * `amountMinor` yalnız KARŞILAŞTIRMA içindir (kendi kaydımız esastır).
 */
final class CallbackResult
{
    public function __construct(
        public readonly bool $valid,
        public readonly ?string $reference = null,      // payments.reference (opak)
        public readonly ?string $providerTxnId = null,
        public readonly ?string $status = null,          // approved | declined
        public readonly ?int $amountMinor = null,        // sağlayıcının bildirdiği tutar (karşılaştırma)
        public readonly ?string $reason = null,          // geçersizlik/red nedeni
    ) {
    }
}
