<?php

declare(strict_types=1);

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use Illuminate\Http\Request;

/**
 * DEMO POS — SUNUM/TANITIM içindir; gerçek para İŞLEMEZ ama HER tutarı ONAYLAR.
 *
 * MockPosProvider tutarın son iki hanesine göre senaryo seçer (..95–..99 → RED);
 * kafe fiyatları çok sık ,90/,95/,99 olduğundan canlı demoda kart reddi + sipariş
 * iptali riski doğar. Bu sağlayıcı bu mayını kaldırır: initiate/charge/query/void/
 * refund DAİMA approved döner (kısa, gerçekçi auth kodu). Testler MockPos'u kullanmaya
 * devam eder (varsayılan 'mock' değişmez); demo kiracısı 'pos_terminal' entegrasyonunu
 * 'demo' seçerek bunu kullanır.
 */
class DemoPosProvider implements PaymentProviderInterface
{
    public function key(): string
    {
        return 'demo';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $this->txn($payment), 'Demo işlem açıldı.');
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        return new ProviderResult(
            ProviderResult::APPROVED,
            $payment->provider_txn_id ?? $this->txn($payment),
            'Onaylandı (demo).',
            ['auth_code' => strtoupper(substr(md5((string) $payment->reference), 0, 6))],
        );
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Onaylı (demo).');
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'İptal onaylandı (demo).');
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        return new ProviderResult(
            ProviderResult::APPROVED,
            ($payment->provider_txn_id ?? 'DEMO').'-R'.substr(bin2hex(random_bytes(3)), 0, 6),
            'İade onaylandı (demo).',
        );
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        return $this->queryPayment($payment);
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        // Demo sağlayıcıda dış callback beklenmez (senkron onay yeterli).
        return new CallbackResult(false, reason: 'Demo sağlayıcı callback kullanmaz.');
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        return new TerminalStatus(true, $terminalId ?? 'DEMO-T1', 'Terminal çevrimiçi (demo).');
    }

    private function txn(Payment $payment): string
    {
        return 'DEMO-'.$payment->reference.'-'.substr(bin2hex(random_bytes(4)), 0, 8);
    }
}
