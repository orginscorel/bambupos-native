<?php

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use Illuminate\Http\Request;

/**
 * Nakit "sağlayıcısı": dış sistem yok; kasiyerin fiziksel tahsilatı
 * kayıt-onaylıdır. Terminal/callback kavramları uygulanmaz.
 */
class CashProvider implements PaymentProviderInterface
{
    public function key(): string
    {
        return 'cash';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, 'cash-'.$payment->reference);
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, 'cash-'.$payment->reference);
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id);
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Nakit iptal — çekmeceden iade edilir.');
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, 'cashref-'.Payment::generateReference(), 'Nakit iade — çekmeceden ödenir.');
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id);
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        return new CallbackResult(false, reason: 'Nakit ödemede callback yoktur.');
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        return new TerminalStatus(true, $terminalId, 'Nakit — terminal gerekmez.');
    }
}
