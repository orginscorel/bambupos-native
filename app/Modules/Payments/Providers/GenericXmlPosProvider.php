<?php

declare(strict_types=1);

namespace App\Modules\Payments\Providers;

use App\Modules\Payments\Contracts\PaymentProviderInterface;
use App\Modules\Payments\Models\Payment;
use App\Modules\Catalog\Support\Money;
use App\Modules\Payments\Services\PosConfigResolver;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Http;

/**
 * JENERİK XML/SOAP BANKA SANAL POS ADAPTÖRÜ — "her şeye uyumlu entegratör"in
 * XML kanadı. Banka-direkt VPOS'lar (NestPay/EST, Garanti GVP, Yapı Kredi POSNet,
 * Param TurkPos…) JSON değil XML/SOAP konuşur. GenericRestPosProvider'ın ikizi:
 * davranış tamamen config'ten gelir (PosConfigResolver → tenant + preset).
 *
 * config.xml:
 *   root: 'CC5Request',                     // istek kök elemanı
 *   form_field: 'DATA' | null,              // set ise XML bu form alanında POST edilir;
 *                                           //   null ise ham XML gövde (text/xml)
 *   envelope: null | 'soap',                // 'soap' → SOAP 1.1 zarfına sarar
 *   soap_action: '...',                     // envelope=soap iken SOAPAction başlığı
 *   requests: { charge:{...}, query:{...}, cancel:{...}, refund:{...} }
 *       // her operasyon için XML gövde şablonu (iç içe dizi). Değerlerde yer
 *       // tutucular: {amount_minor} {amount} {reference} {provider_txn_id}
 *       // {merchant_id} {terminal_id} {refund_amount_minor} {refund_amount}
 * config.map: REST ile aynı ama alanlar SLASH-yol'la okunur ("Transaction/Response/Message").
 *
 * GÜVENLİK (ADR-010): kesin onay yoksa ASLA approved dönme → pending/ERROR.
 * Yapılandırılmamışsa (base_url yok) sahte onay ÜRETİLMEZ.
 */
class GenericXmlPosProvider implements PaymentProviderInterface
{
    public function __construct(private readonly PosConfigResolver $resolver)
    {
    }

    public function key(): string
    {
        return 'generic_soap';
    }

    public function initiatePayment(Payment $payment): ProviderResult
    {
        // Banka VPOS'ta ayrı "initiate" çoğu zaman yok — işlem kimliği yerel üretilir.
        return new ProviderResult(
            ProviderResult::PENDING,
            'XML-'.$payment->reference.'-'.substr(bin2hex(random_bytes(4)), 0, 8),
            'İşlem başlatıldı (yerel referans).',
        );
    }

    public function sendAmountToTerminal(Payment $payment): ProviderResult
    {
        return $this->op($payment, 'charge', defaultUnknown: ProviderResult::PENDING);
    }

    public function queryPayment(Payment $payment): ProviderResult
    {
        return $this->op($payment, 'query', defaultUnknown: ProviderResult::PENDING);
    }

    public function cancelPayment(Payment $payment): ProviderResult
    {
        return $this->op($payment, 'cancel');
    }

    public function refundPayment(Payment $payment, int $amountMinor): ProviderResult
    {
        return $this->op($payment, 'refund', extra: [
            'refund_amount_minor' => (string) $amountMinor,
            'refund_amount' => Money::toDecimalString($amountMinor),
        ]);
    }

    public function reconcilePayment(Payment $payment): ProviderResult
    {
        return $this->queryPayment($payment);
    }

    public function verifyCallback(Request $request): CallbackResult
    {
        $cfg = $this->cfg();
        $secret = (string) Arr::get($cfg, 'callback.secret', Arr::get($cfg, 'auth.secret', ''));

        if ($secret === '') {
            return new CallbackResult(false, reason: 'Callback secret yapılandırılmadı.');
        }

        // Banka callback'i genelde form-POST + alan-hash'idir; sağlayıcıya özgü hash
        // preset'te tanımlanana kadar GÜVENLİ varsayılan: HMAC(raw-body) doğrula.
        $sigHeader = (string) Arr::get($cfg, 'callback.sig_header', 'X-Signature');
        $tsHeader = (string) Arr::get($cfg, 'callback.ts_header', 'X-Timestamp');
        $timestamp = (string) $request->header($tsHeader, (string) $request->input('timestamp', ''));
        $signature = (string) $request->header($sigHeader, (string) $request->input('hash', ''));
        $body = $request->getContent();

        if ($signature === '') {
            return new CallbackResult(false, reason: 'İmza/hash eksik.');
        }

        if ($timestamp !== '') {
            $tolerance = (int) Arr::get($cfg, 'callback.tolerance', config('payments.callback_tolerance_seconds', 300));
            if (! ctype_digit($timestamp) || abs(time() - (int) $timestamp) > $tolerance) {
                return new CallbackResult(false, reason: 'Zaman damgası tolerans dışı.');
            }
        }

        $expected = hash_hmac('sha256', ($timestamp !== '' ? $timestamp.'.' : '').$body, $secret);

        if (! hash_equals($expected, $signature)) {
            return new CallbackResult(false, reason: 'İmza doğrulanamadı.');
        }

        $data = $request->all();
        $statusRaw = (string) ($data['status'] ?? $data['Response'] ?? '');

        return new CallbackResult(
            valid: true,
            reference: isset($data['reference']) ? (string) $data['reference'] : (isset($data['oid']) ? (string) $data['oid'] : null),
            providerTxnId: isset($data['TransId']) ? (string) $data['TransId'] : (isset($data['provider_txn_id']) ? (string) $data['provider_txn_id'] : null),
            status: in_array(strtolower($statusRaw), ['approved', 'success', 'approved'], true) ? ProviderResult::APPROVED : (in_array(strtolower($statusRaw), ['declined', 'error', 'failure'], true) ? ProviderResult::DECLINED : null),
            amountMinor: isset($data['amount_minor']) ? (int) $data['amount_minor'] : null,
        );
    }

    public function getTerminalStatus(?string $terminalId): TerminalStatus
    {
        // Banka VPOS'ta fiziksel terminal yok → erişilebilirlik = base_url yapılandırıldı mı.
        $ok = $this->baseUrl($this->cfg()) !== null;

        return new TerminalStatus($ok, $terminalId, $ok ? 'Sanal POS yapılandırıldı.' : 'Sanal POS yapılandırılmadı.');
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

    /**
     * Bir operasyonu (charge/query/cancel/refund) çalıştırır: XML kur → POST → çöz.
     *
     * @param  array<string, string>  $extra  ek yer tutucu değerleri (iade tutarı vb.)
     */
    private function op(Payment $payment, string $endpointKey, array $extra = [], string $defaultUnknown = ProviderResult::ERROR): ProviderResult
    {
        $cfg = $this->cfg();

        if ($this->baseUrl($cfg) === null) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'Banka sanal POS yapılandırılmadı.');
        }

        $template = (array) Arr::get($cfg, "xml.requests.$endpointKey", []);
        if ($template === []) {
            return new ProviderResult($defaultUnknown, $payment->provider_txn_id, "'$endpointKey' için XML şablonu yok (preset doğrulanmalı).");
        }

        $subs = $this->substitutions($payment, $cfg) + $extra;
        $body = $this->fill($template, $subs);
        $xml = $this->toXml((string) Arr::get($cfg, 'xml.root', 'Request'), $body);

        try {
            $respXml = $this->post($cfg, $endpointKey, $xml);
        } catch (\Throwable $e) {
            return new ProviderResult(ProviderResult::ERROR, $payment->provider_txn_id, 'Bağlantı hatası: '.$e->getMessage());
        }

        $parsed = $this->parseXml($respXml);
        if ($parsed === null) {
            return new ProviderResult($defaultUnknown, $payment->provider_txn_id, 'Yanıt XML çözümlenemedi.');
        }

        $status = $this->mapStatus($parsed, $cfg) ?? $defaultUnknown;
        $txn = $this->getPath($parsed, (string) Arr::get($cfg, 'map.txn_id_field', 'TransId')) ?? $payment->provider_txn_id;
        $auth = $this->getPath($parsed, (string) Arr::get($cfg, 'map.auth_code_field', 'AuthCode'));

        return new ProviderResult(
            $status,
            $txn,
            (string) ($this->getPath($parsed, (string) Arr::get($cfg, 'map.message_field', 'ErrMsg')) ?? $status),
            $auth !== null ? ['auth_code' => $auth] : [],
        );
    }

    /**
     * @param  array<string, mixed>  $cfg
     * @return array<string, string>
     */
    private function substitutions(Payment $payment, array $cfg): array
    {
        return [
            'amount_minor' => (string) $payment->amount_minor,
            'amount' => Money::toDecimalString((int) $payment->amount_minor),
            'reference' => (string) $payment->reference,
            'provider_txn_id' => (string) $payment->provider_txn_id,
            'terminal_id' => (string) ($payment->terminal_id ?? Arr::get($cfg, 'defaults.terminal_id', '')),
            'merchant_id' => (string) Arr::get($cfg, 'merchant_id', ''),
            // Banka kimlikleri XML gövdesinde taşınır (auth.* config'ten).
            'api_user' => (string) Arr::get($cfg, 'auth.username', ''),
            'api_password' => (string) Arr::get($cfg, 'auth.password', ''),
            'store_key' => (string) Arr::get($cfg, 'auth.secret', ''),
        ];
    }

    /**
     * Şablondaki {yer_tutucu} değerlerini doldurur (iç içe dizide özyinelemeli).
     *
     * @param  array<string, mixed>  $tpl
     * @param  array<string, string>  $subs
     * @return array<string, mixed>
     */
    private function fill(array $tpl, array $subs): array
    {
        foreach ($tpl as $k => $v) {
            if (is_array($v)) {
                $tpl[$k] = $this->fill($v, $subs);
            } elseif (is_string($v)) {
                $tpl[$k] = preg_replace_callback('/\{(\w+)\}/', fn ($m) => $subs[$m[1]] ?? $m[0], $v);
            }
        }

        return $tpl;
    }

    /**
     * İç içe diziyi XML'e çevirir.
     *
     * @param  array<string, mixed>  $data
     */
    private function toXml(string $root, array $data): string
    {
        $doc = new \SimpleXMLElement("<?xml version=\"1.0\" encoding=\"UTF-8\"?><{$root}></{$root}>");
        $this->arrayToNode($data, $doc);

        return (string) $doc->asXML();
    }

    /** @param array<string, mixed> $data */
    private function arrayToNode(array $data, \SimpleXMLElement $node): void
    {
        foreach ($data as $key => $value) {
            $tag = is_string($key) ? $key : 'item';
            if (is_array($value)) {
                $this->arrayToNode($value, $node->addChild($tag));
            } else {
                $node->addChild($tag, htmlspecialchars((string) $value, ENT_XML1));
            }
        }
    }

    /**
     * XML/SOAP POST. form_field set ise urlencoded form; değilse ham XML gövde.
     *
     * @param  array<string, mixed>  $cfg
     */
    private function post(array $cfg, string $endpointKey, string $xml): string
    {
        $path = (string) Arr::get($cfg, "endpoints.$endpointKey", '/'.$endpointKey);
        $url = $this->baseUrl($cfg).'/'.ltrim($path, '/');

        if ((string) Arr::get($cfg, 'xml.envelope') === 'soap') {
            $xml = $this->wrapSoap($xml, (string) Arr::get($cfg, 'xml.soap_body_tag', 'Request'));
        }

        $req = Http::timeout((int) Arr::get($cfg, 'timeout', 30));

        $auth = (array) Arr::get($cfg, 'auth', []);
        if (($auth['type'] ?? '') === 'basic') {
            $req = $req->withBasicAuth((string) ($auth['username'] ?? ''), (string) ($auth['password'] ?? ''));
        }

        $formField = Arr::get($cfg, 'xml.form_field');

        if (is_string($formField) && $formField !== '') {
            $response = $req->asForm()->post($url, [$formField => $xml]);
        } else {
            $ct = (string) Arr::get($cfg, 'xml.envelope') === 'soap' ? 'text/xml; charset=utf-8' : 'application/xml';
            $headers = ['Content-Type' => $ct];
            if ($action = Arr::get($cfg, 'xml.soap_action')) {
                $headers['SOAPAction'] = (string) $action;
            }
            $response = $req->withHeaders($headers)->withBody($xml, $ct)->post($url);
        }

        return (string) $response->body();
    }

    private function wrapSoap(string $inner, string $bodyTag): string
    {
        return '<?xml version="1.0" encoding="UTF-8"?>'
            .'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body>'
            .preg_replace('/^<\?xml[^>]*\?>/', '', $inner)
            .'</soap:Body></soap:Envelope>';
    }

    private function parseXml(string $xml): ?\SimpleXMLElement
    {
        if (trim($xml) === '') {
            return null;
        }

        $prev = libxml_use_internal_errors(true);
        try {
            // SOAP zarfını soy (varsa) — Body içeriğini al.
            $xml = preg_replace('/<\/?(\w+:)?(Envelope|Body)[^>]*>/i', '', $xml);
            $node = simplexml_load_string($xml);

            return $node === false ? null : $node;
        } finally {
            libxml_use_internal_errors($prev);
        }
    }

    /** SLASH-yollu XML alan okuma ("Transaction/Response/Message"). */
    private function getPath(\SimpleXMLElement $node, ?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }

        $cur = $node;
        foreach (explode('/', $path) as $seg) {
            if (! isset($cur->{$seg})) {
                return null;
            }
            $cur = $cur->{$seg};
        }

        return trim((string) $cur);
    }

    /** @param array<string, mixed> $cfg */
    private function mapStatus(\SimpleXMLElement $node, array $cfg): ?string
    {
        $raw = (string) ($this->getPath($node, (string) Arr::get($cfg, 'map.status_field', 'Response')) ?? '');
        if ($raw === '') {
            return null;
        }

        $approved = array_map('strval', (array) Arr::get($cfg, 'map.approved', ['Approved', 'Success', '00', '0000']));
        $declined = array_map('strval', (array) Arr::get($cfg, 'map.declined', ['Declined', 'Error', 'Failure']));
        $pending = array_map('strval', (array) Arr::get($cfg, 'map.pending', ['Pending', 'Processing']));

        $needle = strtolower($raw);
        $in = fn (array $s): bool => in_array($needle, array_map('strtolower', $s), true);

        return match (true) {
            $in($approved) => ProviderResult::APPROVED,
            $in($declined) => ProviderResult::DECLINED,
            $in($pending) => ProviderResult::PENDING,
            default => null,
        };
    }
}
