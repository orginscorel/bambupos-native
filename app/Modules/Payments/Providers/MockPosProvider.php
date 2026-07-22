<?php

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use Illuminate\Http\Request;

/**
 * TAM ÇALIŞAN SAHTE POS SAĞLAYICISI — gerçek para İŞLEMEZ.
 *
 * Terminal davranışını tutarın SON İKİ HANESİYLE simüle eder
 * (test/demoda senaryo seçmek için):
 *
 *   ..99  → sendAmountToTerminal DECLINED   (kart reddi)
 *   ..98  → sendAmountToTerminal TIMEOUT    (terminal cevap vermedi;
 *            queryPayment sonra APPROVED döner — "aslında çekilmişti" vakası)
 *   ..97  → sendAmountToTerminal PENDING    (asenkron; imzalı callback bekler)
 *   ..96  → sendAmountToTerminal PENDING; queryPayment DECLINED
 *   ..95  → sendAmountToTerminal ERROR      (ağ hatası; durum bilinmiyor)
 *   diğer → APPROVED (doğrulanmış senkron onay)
 *
 * Gecikme: config('payments.mock.delay_ms') kadar usleep (yoğun saat provası).
 * Terminal: id 'OFFLINE' ise çevrimdışı raporlanır ve gönderim TIMEOUT olur.
 *
 * Callback imzası: HMAC-SHA256( timestamp . '.' . rawBody, secret ) —
 * `X-Pos-Signature` + `X-Pos-Timestamp` başlıkları. ±tolerance dışındaki
 * timestamp REDDEDİLİR (replay penceresi). Test yardımcıları: sign().
 */
class MockPosProvider implements PaymentProviderInterface
{
    public function key(): string
    {
        return 'mock';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        $this->simulateLatency();

        // Sağlayıcı işlem kimliği DAİMA initiate'te üretilir (bizim referans
        // + rastgele ek) — callback/sorgu bu kimlikle eşleşir.
        return new ProviderResult(
            ProviderResult::APPROVED,
            'MOCK-'.$payment->reference.'-'.substr(bin2hex(random_bytes(4)), 0, 8),
            'Mock işlem açıldı.',
            ['initiated_at' => now()->toIso8601String()],
        );
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        $this->simulateLatency();

        if (strtoupper((string) $payment->terminal_id) === 'OFFLINE') {
            return new ProviderResult(ProviderResult::TIMEOUT, $payment->provider_txn_id, 'Terminal çevrimdışı (simülasyon).');
        }

        return match ($this->scenario($payment)) {
            'declined' => new ProviderResult(ProviderResult::DECLINED, $payment->provider_txn_id, 'Kart reddedildi (simülasyon ..99).'),
            'timeout' => new ProviderResult(ProviderResult::TIMEOUT, $payment->provider_txn_id, 'Terminal cevap vermedi (simülasyon ..98).'),
            'pending', 'query_declined' => new ProviderResult(ProviderResult::PENDING, $payment->provider_txn_id, 'Terminal işliyor; callback/sorgu bekleniyor (simülasyon).'),
            'error' => new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'Ağ hatası (simülasyon ..95).'),
            default => new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Onaylandı (simülasyon).', ['auth_code' => strtoupper(substr(md5($payment->reference), 0, 6))]),
        };
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        $this->simulateLatency();

        return match ($this->scenario($payment)) {
            'declined', 'query_declined' => new ProviderResult(ProviderResult::DECLINED, $payment->provider_txn_id, 'Sorgu: işlem reddedilmiş (simülasyon).'),
            // ..98: terminal cevap verememişti ama işlem sağlayıcıda BAŞARILI —
            // "timeout'u başarısız sayma" kuralının test edildiği yol.
            'timeout' => new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Sorgu: işlem onaylı bulundu (simülasyon ..98).'),
            'pending' => new ProviderResult(ProviderResult::PENDING, $payment->provider_txn_id, 'Sorgu: hâlâ işleniyor; callback bekleyin (simülasyon ..97).'),
            'error' => new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'Sorgu: sağlayıcıya ulaşılamadı (simülasyon).'),
            default => new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Sorgu: onaylı (simülasyon).'),
        };
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        $this->simulateLatency();

        return new ProviderResult(ProviderResult::APPROVED, $payment->provider_txn_id, 'Mock void onaylandı.');
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        $this->simulateLatency();

        if ($amountMinor % 100 === 89) { // ..89 → iade reddi senaryosu
            return new ProviderResult(ProviderResult::DECLINED, $payment->provider_txn_id, 'İade reddedildi (simülasyon ..89).');
        }

        return new ProviderResult(
            ProviderResult::APPROVED,
            ($payment->provider_txn_id ?? 'MOCK').'-R'.substr(bin2hex(random_bytes(3)), 0, 6),
            'Mock iade onaylandı.',
        );
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        // Mutabakat = sorgu sonucu; tutar karşılaştırmasını servis yapar.
        return $this->queryPayment($payment);
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        $timestamp = (string) $request->header('X-Pos-Timestamp', '');
        $signature = (string) $request->header('X-Pos-Signature', '');
        $body = $request->getContent();

        if ($timestamp === '' || $signature === '') {
            return new CallbackResult(false, reason: 'İmza/zaman damgası başlığı eksik.');
        }

        // Replay penceresi: eski (veya gelecekteki) zaman damgası reddedilir.
        $tolerance = (int) config('payments.callback_tolerance_seconds', 300);

        if (! ctype_digit($timestamp) || abs(time() - (int) $timestamp) > $tolerance) {
            return new CallbackResult(false, reason: 'Zaman damgası tolerans dışı (replay koruması).');
        }

        $expected = self::sign($timestamp, $body);

        if (! hash_equals($expected, $signature)) {
            return new CallbackResult(false, reason: 'İmza doğrulanamadı.');
        }

        $data = json_decode($body, true);

        if (! is_array($data)) {
            return new CallbackResult(false, reason: 'Gövde çözümlenemedi.');
        }

        return new CallbackResult(
            valid: true,
            reference: isset($data['reference']) ? (string) $data['reference'] : null,
            providerTxnId: isset($data['provider_txn_id']) ? (string) $data['provider_txn_id'] : null,
            status: in_array($data['status'] ?? null, ['approved', 'declined'], true) ? $data['status'] : null,
            amountMinor: isset($data['amount_minor']) ? (int) $data['amount_minor'] : null,
        );
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        return strtoupper((string) $terminalId) === 'OFFLINE'
            ? new TerminalStatus(false, $terminalId, 'Terminal çevrimdışı (simülasyon).')
            : new TerminalStatus(true, $terminalId ?? 'MOCK-T1', 'Terminal çevrimiçi (simülasyon).');
    }

    /* ---- Test/simülasyon yardımcıları ---- */

    /** Callback imzası üretimi (testler de bunu kullanır). */
    public static function sign(string $timestamp, string $rawBody): string
    {
        return hash_hmac('sha256', $timestamp.'.'.$rawBody, self::secret());
    }

    public static function secret(): string
    {
        $secret = (string) config('payments.mock.secret', '');

        // Yapılandırılmamışsa app.key'den türet (mock DIŞINDA kullanılmaz).
        return $secret !== '' ? $secret : hash('sha256', 'mock-pos:'.config('app.key'));
    }

    private function scenario(Payment $payment): string
    {
        return match (((int) $payment->amount_minor) % 100) {
            99 => 'declined',
            98 => 'timeout',
            97 => 'pending',
            96 => 'query_declined',
            95 => 'error',
            default => 'approved',
        };
    }

    private function simulateLatency(): void
    {
        $ms = (int) config('payments.mock.delay_ms', 0);

        if ($ms > 0) {
            usleep(min($ms, 2000) * 1000);
        }
    }
}
