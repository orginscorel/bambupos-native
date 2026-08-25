<?php

declare(strict_types=1);

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Services\PosConfigResolver;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Http;

/**
 * JENERİK REST/TSM POS ADAPTÖRÜ — "her şeye uyumlu entegratör" çekirdeği.
 *
 * TEK kod, ÇOK sağlayıcı: davranış tamamen işletmenin (tenant) config'inden gelir
 * (PosConfigResolver → tenant_integrations + config/payments.presets). Yeni banka /
 * YN-POS / TSM eklemek = config satırı; bu sınıfa dokunulmaz.
 *
 * config alanları (preset + tenant birleşimi):
 *   base_url, auth{type:hmac|bearer|basic, key_id, secret, username, password, header},
 *   endpoints{initiate,charge,query,cancel,refund,status} (base_url'e göreli yol),
 *   map{status_field, approved[], declined[], pending[], txn_id_field, auth_code_field},
 *   callback{sig_header, ts_header, secret, tolerance},
 *   defaults{terminal_id}
 *
 * GÜVENLİK KURALI (ADR-010): senkron cevap KESİN değilse ASLA approved dönme —
 * pending dön, gerçeği queryPayment/verifyCallback belirler. Yapılandırılmamışsa
 * (base_url boş) ERROR döner; sahte onay ÜRETİLMEZ.
 */
class GenericRestPosProvider implements PaymentProviderInterface
{
    public function __construct(private readonly PosConfigResolver $resolver)
    {
    }

    public function key(): string
    {
        return 'generic_rest';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        $cfg = $this->cfg();

        // Yapılandırılmamış: işlem kimliğini yerel üret (akış terminale ilerlesin),
        // ama sağlayıcı çağrısı YOK — tahsilat sendAmountToTerminal'da denenir.
        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(
                ProviderResult::PENDING,
                'GEN-'.$payment->reference.'-'.substr(bin2hex(random_bytes(4)), 0, 8),
                'Sağlayıcı yapılandırılmadı (base_url yok) — yapılandırın.',
            );
        }

        $resp = $this->call($cfg, 'initiate', $this->basePayload($payment));

        return $this->toResult($resp, $cfg, fallbackTxn: 'GEN-'.$payment->reference);
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        $cfg = $this->cfg();

        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'POS sağlayıcısı yapılandırılmadı.');
        }

        $resp = $this->call($cfg, 'charge', $this->basePayload($payment) + [
            'amount_minor' => (int) $payment->amount_minor,
            'terminal_id' => $payment->terminal_id ?? Arr::get($cfg, 'defaults.terminal_id'),
        ]);

        // Terminal işlemi çoğu TSM'de ASENKRONdur → kesin onay gelmezse PENDING.
        return $this->toResult($resp, $cfg, $payment->provider_txn_id, defaultUnknown: ProviderResult::PENDING);
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        $cfg = $this->cfg();

        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'POS sağlayıcısı yapılandırılmadı.');
        }

        $resp = $this->call($cfg, 'query', $this->basePayload($payment));

        return $this->toResult($resp, $cfg, $payment->provider_txn_id, defaultUnknown: ProviderResult::PENDING);
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        $cfg = $this->cfg();

        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'POS sağlayıcısı yapılandırılmadı.');
        }

        return $this->toResult($this->call($cfg, 'cancel', $this->basePayload($payment)), $cfg, $payment->provider_txn_id);
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        $cfg = $this->cfg();

        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'POS sağlayıcısı yapılandırılmadı.');
        }

        $resp = $this->call($cfg, 'refund', $this->basePayload($payment) + ['refund_amount_minor' => $amountMinor]);

        return $this->toResult($resp, $cfg, $payment->provider_txn_id);
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        return $this->queryPayment($payment);
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        $cfg = $this->cfg();
        $sigHeader = (string) Arr::get($cfg, 'callback.sig_header', 'X-Pos-Signature');
        $tsHeader = (string) Arr::get($cfg, 'callback.ts_header', 'X-Pos-Timestamp');
        $secret = (string) Arr::get($cfg, 'callback.secret', Arr::get($cfg, 'auth.secret', ''));

        $timestamp = (string) $request->header($tsHeader, '');
        $signature = (string) $request->header($sigHeader, '');
        $body = $request->getContent();

        if ($secret === '') {
            return new CallbackResult(false, reason: 'Callback secret yapılandırılmadı.');
        }

        if ($timestamp === '' || $signature === '') {
            return new CallbackResult(false, reason: 'İmza/zaman damgası başlığı eksik.');
        }

        $tolerance = (int) Arr::get($cfg, 'callback.tolerance', config('payments.callback_tolerance_seconds', 300));

        if (! ctype_digit($timestamp) || abs(time() - (int) $timestamp) > $tolerance) {
            return new CallbackResult(false, reason: 'Zaman damgası tolerans dışı (replay koruması).');
        }

        $expected = hash_hmac('sha256', $timestamp.'.'.$body, $secret);

        if (! hash_equals($expected, $signature)) {
            return new CallbackResult(false, reason: 'İmza doğrulanamadı.');
        }

        $data = json_decode($body, true);

        if (! is_array($data)) {
            return new CallbackResult(false, reason: 'Gövde çözümlenemedi.');
        }

        $status = $this->mapStatus($data, $cfg);

        return new CallbackResult(
            valid: true,
            reference: isset($data['reference']) ? (string) $data['reference'] : null,
            providerTxnId: $this->extract($data, Arr::get($cfg, 'map.txn_id_field', 'provider_txn_id')),
            status: in_array($status, [ProviderResult::APPROVED, ProviderResult::DECLINED], true) ? $status : null,
            amountMinor: isset($data['amount_minor']) ? (int) $data['amount_minor'] : null,
        );
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        $cfg = $this->cfg();
        $tid = $terminalId ?? Arr::get($cfg, 'defaults.terminal_id');

        if ($this->baseUrl($cfg) === null || ! Arr::has($cfg, 'endpoints.status')) {
            // Durum ucu yoksa "bilinmiyor" yerine iyimser çevrimiçi dönmeyiz —
            // yapılandırma yoksa çevrimdışı raporla (yanıltıcı "hazır" olmasın).
            return new TerminalStatus($this->baseUrl($cfg) !== null, $tid, 'Terminal durum ucu yapılandırılmadı.');
        }

        try {
            $resp = $this->call($cfg, 'status', ['terminal_id' => $tid]);
            $online = (bool) ($resp['online'] ?? ($resp['status'] ?? null) === 'online');

            return new TerminalStatus($online, $tid, $online ? 'Terminal çevrimiçi.' : 'Terminal çevrimdışı.');
        } catch (\Throwable $e) {
            return new TerminalStatus(false, $tid, 'Terminal durumu alınamadı: '.$e->getMessage());
        }
    }

    /* =================== iç yardımcılar =================== */

    /** @return array<string, mixed> */
    private function cfg(): array
    {
        return $this->resolver->forCurrentTenant() ?? [];
    }

    /** @param array<string, mixed> $cfg */
    private function baseUrl(array $cfg): ?string
    {
        $url = (string) ($cfg['base_url'] ?? '');

        return $url !== '' ? rtrim($url, '/') : null;
    }

    /** @return array<string, mixed> */
    private function basePayload(Payment $payment): array
    {
        return [
            'reference' => $payment->reference,
            'provider_txn_id' => $payment->provider_txn_id,
            'merchant_id' => Arr::get($this->cfg(), 'merchant_id'),
        ];
    }

    /**
     * Sağlayıcıya HTTP çağrısı yapar; yanıtı dizi olarak döner.
     *
     * @param  array<string, mixed>  $cfg
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function call(array $cfg, string $endpointKey, array $payload): array
    {
        $path = (string) Arr::get($cfg, "endpoints.$endpointKey", '/'.$endpointKey);
        $url = $this->baseUrl($cfg).'/'.ltrim($path, '/');

        $req = Http::asJson()
            ->timeout((int) Arr::get($cfg, 'timeout', 30))
            ->acceptJson();

        $auth = (array) Arr::get($cfg, 'auth', []);
        $type = (string) ($auth['type'] ?? '');

        if ($type === 'bearer') {
            $req = $req->withToken((string) ($auth['secret'] ?? $auth['token'] ?? ''));
        } elseif ($type === 'basic') {
            $req = $req->withBasicAuth((string) ($auth['username'] ?? ''), (string) ($auth['password'] ?? ''));
        } elseif ($type === 'hmac') {
            // İmzalı istek: HMAC-SHA256(json_body, secret) özel başlıkta.
            $bodyJson = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $sig = hash_hmac('sha256', (string) $bodyJson, (string) ($auth['secret'] ?? ''));
            $req = $req->withHeaders([
                (string) ($auth['header'] ?? 'X-Signature') => $sig,
                (string) ($auth['key_header'] ?? 'X-Key-Id') => (string) ($auth['key_id'] ?? ''),
            ]);
        }

        $response = $req->post($url, $payload);

        return is_array($response->json()) ? $response->json() : [];
    }

    /**
     * Sağlayıcı yanıtını normalize ProviderResult'a çevirir (config map ile).
     *
     * @param  array<string, mixed>  $resp
     * @param  array<string, mixed>  $cfg
     */
    private function toResult(array $resp, array $cfg, ?string $fallbackTxn = null, string $defaultUnknown = ProviderResult::ERROR): ProviderResult
    {
        if ($resp === []) {
            return new ProviderResult($defaultUnknown, $fallbackTxn, 'Sağlayıcıdan boş/başarısız yanıt.');
        }

        $status = $this->mapStatus($resp, $cfg) ?? $defaultUnknown;
        $txn = $this->extract($resp, Arr::get($cfg, 'map.txn_id_field', 'provider_txn_id')) ?? $fallbackTxn;
        $authCode = $this->extract($resp, Arr::get($cfg, 'map.auth_code_field', 'auth_code'));

        return new ProviderResult(
            $status,
            $txn,
            (string) ($resp['message'] ?? Arr::get($cfg, 'labels.'.$status, $status)),
            $authCode !== null ? ['auth_code' => $authCode] : [],
        );
    }

    /**
     * Yanıttaki durum alanını config map'ine göre normalize eder.
     *
     * @param  array<string, mixed>  $resp
     * @param  array<string, mixed>  $cfg
     */
    private function mapStatus(array $resp, array $cfg): ?string
    {
        $field = (string) Arr::get($cfg, 'map.status_field', 'status');
        $raw = (string) ($this->extract($resp, $field) ?? '');

        if ($raw === '') {
            return null;
        }

        $approved = array_map('strval', (array) Arr::get($cfg, 'map.approved', ['approved', 'success', '00', 'ok']));
        $declined = array_map('strval', (array) Arr::get($cfg, 'map.declined', ['declined', 'failed', 'error']));
        $pending = array_map('strval', (array) Arr::get($cfg, 'map.pending', ['pending', 'processing', 'wait']));

        $needle = strtolower($raw);
        $in = fn (array $set): bool => in_array($needle, array_map('strtolower', $set), true);

        return match (true) {
            $in($approved) => ProviderResult::APPROVED,
            $in($declined) => ProviderResult::DECLINED,
            $in($pending) => ProviderResult::PENDING,
            default => null,
        };
    }

    /**
     * Nokta-yollu alan okuma ("data.transactionId").
     *
     * @param  array<string, mixed>  $data
     */
    private function extract(array $data, ?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }

        $val = Arr::get($data, $path);

        return $val === null ? null : (string) $val;
    }
}
