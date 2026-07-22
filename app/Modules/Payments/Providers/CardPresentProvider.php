<?php

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use Illuminate\Http\Request;

/**
 * Fiziksel POS "kayıt" sağlayıcısı (ADR-010 v1): tahsilat masadaki
 * BANKA POS'unda yapılmıştır; sistemdeki kayıt kasiyer beyanıdır.
 * Entegre terminal yönetimi MockPosProvider/SandboxPosProvider'dadır.
 */
class CardPresentProvider implements PaymentProviderInterface
{
    public function key(): string
    {
        return 'card_present';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, 'cp-'.$payment->reference);
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        // Entegrasyonsuz banka POS'una tutar gönderilemez; kasiyer terminali
        // elle kullanır, kaydı onaylar. "approved" = kasiyer beyanı.
        return new ProviderResult(ProviderResult::APPROVED, 'cp-'.$payment->reference, 'Kayıt-onaylı (entegrasyonsuz POS).');
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id);
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'İptali banka POS\'unda da yapmayı unutmayın.');
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, 'cpref-'.Payment::generateReference(), 'İadeyi banka POS\'unda da yapmayı unutmayın.');
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::PENDING, $payment->provider_txn_id, 'Entegrasyonsuz POS: mutabakat gün sonu slip toplamıyla elle yapılır.');
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        return new CallbackResult(false, reason: 'Entegrasyonsuz POS\'ta callback yoktur.');
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        return new TerminalStatus(true, $terminalId, 'Entegrasyonsuz POS — durum izlenmez.');
    }
}
