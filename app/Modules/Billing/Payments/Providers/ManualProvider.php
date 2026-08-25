<?php

namespace App\Modules\Billing\Payments\Providers;

use App\Modules\Billing\Models\SaasInvoice;
use App\Modules\Billing\Payments\Contracts\SaasPaymentProvider;
use App\Modules\Billing\Payments\Support\SaasCallbackResult;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * VARSAYILAN sağlayıcı (SAAS_PAYMENT_PROVIDER boş/'manual' iken). Dış
 * sistem YOK, çevrimiçi ödeme sayfası YOK — canlı tahsilat bu modda
 * kesinlikle olmaz. Süper-admin faturayı elle "ödendi" işaretler
 * (SaasBillingActionController::markPaid → BillingService::markPaid).
 */
class ManualProvider implements SaasPaymentProvider
{
    public function key(): string
    {
        return 'manual';
    }

    public function checkoutUrl(SaasInvoice $invoice): string
    {
        throw new RuntimeException(
            'Bu işletme için çevrimiçi ödeme henüz aktif değil (manuel mod). '
            .'Lütfen bizimle iletişime geçin; ödemeniz elle işlenecektir.'
        );
    }

    public function verifyCallback(Request $request): SaasCallbackResult
    {
        return new SaasCallbackResult(false, reason: 'Manuel modda sağlayıcı callback/webhook kabul edilmez.');
    }

    public function expectsPlainTextResponse(): bool
    {
        return false;
    }
}
