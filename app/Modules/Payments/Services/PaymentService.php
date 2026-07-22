<?php

namespace App\Modules\Payments\Services;

use App\Modules\Catalog\Support\Money;
use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Payments\Enums\CashMovementType;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Providers\ProviderRegistry;
use App\Modules\Payments\Providers\ProviderResult;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Ödeme çekirdeği (Faz-5, ADR-010). PARA DEĞİŞMEZLERİ:
 *
 *  1. SUM(payments başarılı) == orders.paid_minor — paid_minor yalnız
 *     OrderService::applyPaidDelta ile, ödeme satırıyla AYNI transaction'da
 *     değişir; başka yazan yoktur.
 *  2. Aşırı tahsil YASAK: tutar kalan tutarı aşamaz (bekleyen terminal
 *     ödemeleri de kalandan düşülür). Terminalde ÇEKİLMİŞ fazlalık
 *     (onay anındaki yarış) reddedilemez — bahşiş olarak AÇIKÇA işaretlenir.
 *  3. Çift işleme YOK: Idempotency-Key + UNIQUE(provider, provider_txn_id)
 *     + durum makinesi (Pending→Succeeded tek yön, tek sefer).
 *  4. Terminale gönderim ≠ tahsilat: yalnız doğrulanmış senkron onay /
 *     imzalı callback / sorgu sonucu Succeeded yapar.
 *  5. Başarısız ödeme adisyonu KAPATMAZ (paid_minor'a hiç dokunmaz).
 *  6. Tüm mutasyonlar DB::transaction + lockForUpdate + sürüm denetimi
 *     (OrderService::withLockedOrder) içindedir.
 */
class PaymentService
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly ProviderRegistry $providers,
        private readonly CashSessionService $cash,
        private readonly AuditLogger $audit,
    ) {
    }

    /* =========================================================
     |  Tahsilat
     * ========================================================= */

    /**
     * Ödeme alma girişi. Terminal yöntemleri (kredi/banka kartı, provider
     * terminal ise) asenkron akışa gider; diğerleri anında tahsil edilir.
     *
     * @param array{
     *   method: string, amount_minor: int, tip_minor?: int,
     *   tendered_minor?: int|null, note?: string|null, round?: bool,
     *   provider?: string|null, terminal_id?: string|null,
     *   cash_register_id?: int|null
     * } $data
     * @return array{payment: Payment, provider_result: ?ProviderResult}
     */
    public function pay(Order $order, array $data, User $actor, ?int $expectedVersion = null): array
    {
        $method = PaymentMethod::from($data['method']);
        $providerKey = $this->providers->keyForMethod($method, $data['provider'] ?? null);

        // Terminal akışı: mock/sandbox sağlayıcıya bağlı kart ödemeleri.
        if ($method->usesTerminal() && ! in_array($providerKey, ['cash', 'card_present'], true)) {
            return $this->initiateTerminalPayment($order, $data, $method, $providerKey, $actor, $expectedVersion);
        }

        return ['payment' => $this->payInstant($order, $data, $method, $providerKey, $actor, $expectedVersion), 'provider_result' => null];
    }

    /**
     * Anında (kayıt-onaylı) tahsilat: nakit, entegrasyonsuz kart, yemek
     * kartı, havale, QR, açık hesap, hediye kartı.
     */
    private function payInstant(Order $order, array $data, PaymentMethod $method, string $providerKey, User $actor, ?int $expectedVersion): Payment
    {
        $amount = (int) $data['amount_minor'];
        $tip = max(0, (int) ($data['tip_minor'] ?? 0));

        if ($amount <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['Tutar pozitif olmalı.']]);
        }

        return $this->orders->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($data, $method, $providerKey, $actor, $amount, $tip): Payment {
            // Nakit yuvarlama: kalan tutar adım değerine yuvarlanır (±99 kuruş).
            if (($data['round'] ?? false) && $method === PaymentMethod::Cash) {
                $this->applyCashRounding($locked, $actor);
            }

            $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);
            $pendingTotal = $this->pendingTotalMinor($locked);

            // Aşırı tahsil reddi: bekleyen terminal ödemeleri de rezerv sayılır.
            if ($amount > $remaining - $pendingTotal) {
                throw ValidationException::withMessages(['amount_minor' => [
                    $pendingTotal > 0
                        ? 'Tutar, bekleyen terminal ödemeleri düşüldükten sonraki kalanı ('.Money::toDecimalString(max(0, $remaining - $pendingTotal)).' TL) aşamaz. Fazlasını bahşiş alanına yazın.'
                        : 'Tutar kalan tutarı ('.Money::toDecimalString($remaining).' TL) aşamaz. Fazlasını bahşiş alanına yazın.',
                ]]);
            }

            // Nakit: verilen para & para üstü tutarlılığı.
            $tendered = isset($data['tendered_minor']) ? (int) $data['tendered_minor'] : null;
            $change = 0;

            if ($method === PaymentMethod::Cash && $tendered !== null) {
                if ($tendered < $amount + $tip) {
                    throw ValidationException::withMessages(['tendered_minor' => ['Verilen para, tutar + bahşiş toplamından az olamaz.']]);
                }

                $change = $tendered - $amount - $tip;
            }

            $session = $this->cash->resolveOpenSession($locked, $data['cash_register_id'] ?? null);

            $payment = new Payment([
                'kind' => 'payment',
                'method' => $method->value,
                'status' => PaymentStatus::Succeeded->value,
                'amount_minor' => $amount,
                'tip_minor' => $tip,
                'tendered_minor' => $tendered,
                'change_minor' => $change,
                'currency' => (string) ($locked->currency ?? 'TRY'),
                'provider' => $providerKey,
                'note' => $data['note'] ?? null,
            ]);
            $payment->tenant_id = $locked->tenant_id;
            $payment->branch_id = $locked->branch_id;
            $payment->order_id = $locked->getKey();
            $payment->reference = Payment::generateReference();
            $payment->provider_txn_id = $providerKey.'-'.$payment->reference;
            $payment->cash_session_id = $session?->getKey();
            $payment->cashier_id = $actor->getKey();
            $payment->paid_at = now();
            $payment->save();

            // paid_minor AYNI transaction'da türetilir (değişmez #1).
            $this->orders->applyPaidDelta($locked, $amount, $method->value, $actor, [
                'payment_id' => $payment->getKey(),
                'tip_minor' => $tip,
            ]);

            // Nakit çekmece hareketi (tutar + bahşiş çekmeceye girer).
            if ($method->affectsCashDrawer() && $session !== null) {
                $this->cash->recordPaymentMovement($session, $payment, CashMovementType::Payment, $amount + $tip, $actor);
            }

            $this->audit->log('payments.taken', $payment, null, [
                'order_id' => $locked->getKey(),
                'method' => $method->value,
                'amount_minor' => $amount,
                'tip_minor' => $tip,
                'performed_by' => $actor->getKey(),
            ]);

            return $payment;
        });
    }

    /**
     * Terminal akışı 1/2: bekleyen ödeme kaydı + terminale gönderim.
     * KURAL: gönderim ödemeyi TAMAMLAMAZ; yalnız doğrulanmış sonuç
     * (senkron onay / callback / sorgu) settle() ile tamamlar.
     *
     * @return array{payment: Payment, provider_result: ProviderResult}
     */
    private function initiateTerminalPayment(Order $order, array $data, PaymentMethod $method, string $providerKey, User $actor, ?int $expectedVersion): array
    {
        $amount = (int) $data['amount_minor'];
        $tip = max(0, (int) ($data['tip_minor'] ?? 0));

        if ($amount <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['Tutar pozitif olmalı.']]);
        }

        /** @var Payment $payment */
        $payment = $this->orders->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($data, $method, $providerKey, $actor, $amount, $tip): Payment {
            $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);
            $pendingTotal = $this->pendingTotalMinor($locked);

            if ($amount > $remaining - $pendingTotal) {
                throw ValidationException::withMessages(['amount_minor' => [
                    'Tutar kalan tutarı ('.Money::toDecimalString(max(0, $remaining - $pendingTotal)).' TL) aşamaz (bekleyen terminal ödemeleri dahil).',
                ]]);
            }

            $session = $this->cash->resolveOpenSession($locked, $data['cash_register_id'] ?? null);

            $payment = new Payment([
                'kind' => 'payment',
                'method' => $method->value,
                'status' => PaymentStatus::Pending->value,
                'amount_minor' => $amount,
                'tip_minor' => $tip,
                'currency' => (string) ($locked->currency ?? 'TRY'),
                'provider' => $providerKey,
                'terminal_id' => $data['terminal_id'] ?? null,
                'note' => $data['note'] ?? null,
            ]);
            $payment->tenant_id = $locked->tenant_id;
            $payment->branch_id = $locked->branch_id;
            $payment->order_id = $locked->getKey();
            $payment->reference = Payment::generateReference();
            $payment->cash_session_id = $session?->getKey();
            $payment->cashier_id = $actor->getKey();
            $payment->save();

            return $payment;
        });

        // Sağlayıcı çağrıları TRANSACTION DIŞINDA (ağ çağrısı kilit tutmaz).
        $provider = $this->providers->get($providerKey);

        $init = $provider->initiatePayment($payment);

        if ($init->providerTxnId !== null) {
            $payment->provider_txn_id = $init->providerTxnId;
            $payment->save();
        }

        $send = $provider->sendAmountToTerminal($payment);

        if ($send->approved()) {
            // Doğrulanmış SENKRON onay — tamamlanabilir.
            $payment = $this->settle($payment, $send, $actor);
        } elseif ($send->declined()) {
            $payment = $this->markFailed($payment, $send, $actor);
        } else {
            // pending/timeout/error: DURUM BİLİNMİYOR — asla başarısız sayma;
            // ödeme Pending kalır, callback ya da sorgu netleştirir.
            $payment->meta = array_merge((array) $payment->meta, ['last_send' => ['status' => $send->status, 'message' => $send->message]]);
            $payment->save();
        }

        return ['payment' => $payment->fresh(), 'provider_result' => $send];
    }

    /** Bekleyen ödemeyi sağlayıcıdan SORGULAYARAK netleştirir. */
    public function queryAndSettle(Payment $payment, ?User $actor): array
    {
        if ($payment->statusEnum() !== PaymentStatus::Pending) {
            return ['payment' => $payment, 'provider_result' => null];
        }

        $result = $this->providers->get((string) $payment->provider)->queryPayment($payment);

        if ($result->approved()) {
            $payment = $this->settle($payment, $result, $actor);
        } elseif ($result->declined()) {
            $payment = $this->markFailed($payment, $result, $actor);
        }
        // unknown → Pending kalır (dürüst belirsizlik)

        return ['payment' => $payment->fresh(), 'provider_result' => $result];
    }

    /**
     * DOĞRULANMIŞ sağlayıcı onayını ödemeye işler (tek tamamlanma yolu).
     * Replay-güvenli: zaten Succeeded ise İKİNCİ kez işlemez.
     */
    public function settle(Payment $payment, ProviderResult $result, ?User $actor): Payment
    {
        if (! $result->approved()) {
            throw new \LogicException('settle() yalnız onaylanmış sonuçla çağrılabilir.');
        }

        $order = Order::withoutTenancy()->findOrFail($payment->order_id);

        return $this->orders->withLockedOrder($order, null, function (Order $locked) use ($payment, $result, $actor): Payment {
            /** @var Payment $fresh */
            $fresh = Payment::withoutTenancy()->lockForUpdate()->findOrFail($payment->getKey());

            // Replay koruması: yalnız Pending → Succeeded geçilir; tekrar
            // gelen callback/sorgu aynı kaydı DEĞİŞTİRMEDEN döner.
            if ($fresh->statusEnum() === PaymentStatus::Succeeded) {
                return $fresh;
            }

            if (! $fresh->statusEnum()->canTransitionTo(PaymentStatus::Succeeded)) {
                throw ValidationException::withMessages(['payment' => [
                    'Ödeme "'.$fresh->statusEnum()->label().'" durumundan tamamlanamaz.',
                ]]);
            }

            $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);
            $apply = min((int) $fresh->amount_minor, $remaining);
            $excess = (int) $fresh->amount_minor - $apply;

            // Terminalde ÇEKİLMİŞ parayı reddedemeyiz (yarış: onay beklerken
            // başka ödeme kalanı kapattı) → fazlalık AÇIKÇA bahşiş olur.
            if ($excess > 0) {
                $fresh->tip_minor = (int) $fresh->tip_minor + $excess;
            }

            $fresh->status = PaymentStatus::Succeeded->value;
            $fresh->paid_at = now();

            if ($result->providerTxnId !== null) {
                $fresh->provider_txn_id = $result->providerTxnId;
            }

            $fresh->meta = array_merge((array) $fresh->meta, ['settle' => ['message' => $result->message] + $result->raw]);
            $fresh->save();

            if ($apply > 0) {
                $this->orders->applyPaidDelta($locked, $apply, (string) $fresh->method, $actor, [
                    'payment_id' => $fresh->getKey(),
                    'provider' => $fresh->provider,
                    'provider_txn_id' => $fresh->provider_txn_id,
                ]);
            }

            if ($excess > 0) {
                $this->audit->log('payments.overpayment_marked_as_tip', $fresh, null, [
                    'excess_minor' => $excess,
                    'order_id' => $locked->getKey(),
                ]);
            }

            $this->audit->log('payments.settled', $fresh, null, [
                'order_id' => $locked->getKey(),
                'amount_minor' => (int) $fresh->amount_minor,
                'provider_txn_id' => $fresh->provider_txn_id,
            ]);

            return $fresh;
        });
    }

    /** Başarısız ödeme: adisyona DOKUNMAZ (değişmez #5). */
    public function markFailed(Payment $payment, ProviderResult $result, ?User $actor): Payment
    {
        return DB::transaction(function () use ($payment, $result): Payment {
            /** @var Payment $fresh */
            $fresh = Payment::withoutTenancy()->lockForUpdate()->findOrFail($payment->getKey());

            if ($fresh->statusEnum() !== PaymentStatus::Pending) {
                return $fresh; // yalnız bekleyen ödeme başarısız işaretlenebilir
            }

            $fresh->status = PaymentStatus::Failed->value;
            $fresh->reason = $result->message;
            $fresh->meta = array_merge((array) $fresh->meta, ['fail' => ['status' => $result->status, 'message' => $result->message]]);
            $fresh->save();

            return $fresh;
        });
    }

    /* =========================================================
     |  Callback (imzalı, replay-korumalı)
     * ========================================================= */

    /**
     * Sağlayıcı callback'i: imza + zaman damgası provider->verifyCallback'te
     * doğrulanır; TUTAR kendi kaydımızdan alınır, callback'tekiyle yalnız
     * KARŞILAŞTIRILIR — uyuşmazlık işleme değil `suspect` alarmına gider.
     *
     * @return array{ok: bool, message: string, payment: ?Payment}
     */
    public function handleCallback(string $providerKey, \Illuminate\Http\Request $request): array
    {
        if (! $this->providers->has($providerKey)) {
            return ['ok' => false, 'message' => 'Bilinmeyen sağlayıcı.', 'payment' => null];
        }

        $callback = $this->providers->get($providerKey)->verifyCallback($request);

        if (! $callback->valid) {
            return ['ok' => false, 'message' => 'Doğrulama başarısız: '.($callback->reason ?? 'imza'), 'payment' => null];
        }

        // Eşleme: önce opak referans, sonra sağlayıcı işlem kimliği.
        $payment = null;

        if ($callback->reference !== null) {
            $payment = Payment::withoutTenancy()->where('reference', $callback->reference)->first();
        }

        if ($payment === null && $callback->providerTxnId !== null) {
            $payment = Payment::withoutTenancy()
                ->where('provider', $providerKey)
                ->where('provider_txn_id', $callback->providerTxnId)
                ->first();
        }

        if ($payment === null) {
            return ['ok' => false, 'message' => 'Ödeme kaydı bulunamadı.', 'payment' => null];
        }

        // Tutar karşılaştırması (ADR-010): uyuşmazlık = suspect + alarm.
        if ($callback->amountMinor !== null && $callback->amountMinor !== (int) $payment->amount_minor) {
            if (! $payment->suspect) {
                $payment->suspect = true;
                $payment->suspect_reason = sprintf(
                    'Callback tutarı uyuşmuyor: bizde %d, sağlayıcıda %d kuruş.',
                    (int) $payment->amount_minor,
                    $callback->amountMinor,
                );
                $payment->save();

                $this->audit->log('payments.suspect', $payment, null, [
                    'reason' => $payment->suspect_reason,
                ]);
            }

            return ['ok' => false, 'message' => 'Tutar uyuşmazlığı; işlem şüpheli olarak işaretlendi.', 'payment' => $payment];
        }

        if ($callback->status === 'approved') {
            $settled = $this->settle($payment, new ProviderResult(ProviderResult::APPROVED, $callback->providerTxnId, 'callback'), null);

            return ['ok' => true, 'message' => 'OK', 'payment' => $settled];
        }

        if ($callback->status === 'declined') {
            $failed = $this->markFailed($payment, new ProviderResult(ProviderResult::DECLINED, $callback->providerTxnId, 'callback: declined'), null);

            return ['ok' => true, 'message' => 'OK (declined)', 'payment' => $failed];
        }

        return ['ok' => false, 'message' => 'Geçersiz callback durumu.', 'payment' => $payment];
    }

    /* =========================================================
     |  Void (ödeme iptali) & iade
     * ========================================================= */

    /**
     * Ödeme iptali (void): tahsilat hiç olmamış sayılır; paid_minor düşer,
     * kapanmış adisyon yeniden açılır, nakit ise ters kasa hareketi yazılır.
     */
    public function void(Payment $payment, string $reason, User $actor, ?int $expectedVersion = null): Payment
    {
        $order = Order::withoutTenancy()->findOrFail($payment->order_id);

        return $this->orders->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($payment, $reason, $actor): Payment {
            /** @var Payment $fresh */
            $fresh = Payment::withoutTenancy()->lockForUpdate()->findOrFail($payment->getKey());
            $status = $fresh->statusEnum();

            if ($fresh->kind !== 'payment') {
                throw ValidationException::withMessages(['payment' => ['İade kaydı void edilemez.']]);
            }

            if (! $status->canTransitionTo(PaymentStatus::Cancelled)) {
                throw ValidationException::withMessages(['payment' => ['"'.$status->label().'" durumundaki ödeme iptal edilemez.']]);
            }

            if ($fresh->refundedTotalMinor() > 0) {
                throw ValidationException::withMessages(['payment' => ['Kısmi iadesi olan ödeme void edilemez; kalan için iade kullanın.']]);
            }

            // Sağlayıcı void'i (terminal yöntemleri): reddederse durmalıyız.
            if ($status === PaymentStatus::Succeeded || $status === PaymentStatus::Pending) {
                $providerKey = (string) $fresh->provider;

                if ($this->providers->has($providerKey)) {
                    $result = $this->providers->get($providerKey)->cancelPayment($fresh);

                    if ($result->declined()) {
                        throw ValidationException::withMessages(['payment' => [
                            'Sağlayıcı iptali reddetti: '.($result->message ?? '').' İade akışını kullanın.',
                        ]]);
                    }

                    if ($result->unknown() && $fresh->methodEnum()->usesTerminal() && ! in_array($providerKey, ['cash', 'card_present'], true)) {
                        throw ValidationException::withMessages(['payment' => [
                            'Sağlayıcıya ulaşılamadı; iptal durumu belirsiz. Tekrar deneyin.',
                        ]]);
                    }
                }
            }

            $wasCollected = $status === PaymentStatus::Succeeded;

            $fresh->status = PaymentStatus::Cancelled->value;
            $fresh->reason = $reason;
            $fresh->save();

            if ($wasCollected) {
                $this->orders->applyPaidDelta($locked, -((int) $fresh->amount_minor), (string) $fresh->method, $actor, [
                    'payment_id' => $fresh->getKey(),
                    'reason' => $reason,
                ]);

                // Nakitse çekmeceden çıkışı ters kayıtla izle.
                if ($fresh->methodEnum()->affectsCashDrawer()) {
                    $this->cash->recordPaymentReversal($fresh, $actor, $reason);
                }
            }

            $this->audit->log('payments.voided', $fresh, ['status' => $status->value], [
                'order_id' => $locked->getKey(),
                'amount_minor' => (int) $fresh->amount_minor,
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $fresh;
        });
    }

    /**
     * Kısmi/tam iade: iade AYRI bir payments satırıdır (kind=refund,
     * refund_of_id). orders.refunded_minor aynı transaction'da türetilir.
     */
    public function refund(Payment $payment, int $amountMinor, string $reason, User $actor, ?int $expectedVersion = null): Payment
    {
        if ($amountMinor <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['İade tutarı pozitif olmalı.']]);
        }

        $order = Order::withoutTenancy()->findOrFail($payment->order_id);

        // Sağlayıcı iadesi TRANSACTION DIŞINDA denenir (kilit tutmaz);
        // reddedilirse hiçbir kayıt açılmaz.
        /** @var Payment $original */
        $original = Payment::withoutTenancy()->findOrFail($payment->getKey());

        if ($original->kind !== 'payment' || ! in_array($original->statusEnum(), [PaymentStatus::Succeeded, PaymentStatus::PartiallyRefunded], true)) {
            throw ValidationException::withMessages(['payment' => ['Yalnız başarılı ödeme iade edilebilir.']]);
        }

        $providerKey = (string) $original->provider;
        $providerRef = null;

        if ($this->providers->has($providerKey)) {
            $result = $this->providers->get($providerKey)->refundPayment($original, $amountMinor);

            if (! $result->approved()) {
                throw ValidationException::withMessages(['payment' => [
                    'Sağlayıcı iadeyi onaylamadı: '.($result->message ?? $result->status),
                ]]);
            }

            $providerRef = $result->providerTxnId;
        }

        return $this->orders->withLockedOrder($order, $expectedVersion, function (Order $locked) use ($original, $amountMinor, $reason, $actor, $providerKey, $providerRef): Payment {
            /** @var Payment $fresh */
            $fresh = Payment::withoutTenancy()->lockForUpdate()->findOrFail($original->getKey());

            $alreadyRefunded = $fresh->refundedTotalMinor();

            if ($alreadyRefunded + $amountMinor > (int) $fresh->amount_minor) {
                throw ValidationException::withMessages(['amount_minor' => [
                    'İade toplamı ödeme tutarını aşamaz (kalan: '.Money::toDecimalString((int) $fresh->amount_minor - $alreadyRefunded).' TL).',
                ]]);
            }

            $session = $this->cash->resolveOpenSession($locked, null);

            $refund = new Payment([
                'kind' => 'refund',
                'method' => $fresh->method,
                'status' => PaymentStatus::Succeeded->value,
                'amount_minor' => $amountMinor,
                'currency' => $fresh->currency,
                'provider' => $providerKey,
                'reason' => $reason,
            ]);
            $refund->tenant_id = $locked->tenant_id;
            $refund->branch_id = $locked->branch_id;
            $refund->order_id = $locked->getKey();
            $refund->reference = Payment::generateReference();
            $refund->refund_of_id = $fresh->getKey();
            $refund->provider_txn_id = $providerRef ?? ($providerKey.'-ref-'.$refund->reference);
            $refund->cash_session_id = $session?->getKey();
            $refund->cashier_id = $actor->getKey();
            $refund->paid_at = now();
            $refund->save();

            $this->orders->applyRefundDelta($locked, $amountMinor, $actor, [
                'payment_id' => $fresh->getKey(),
                'refund_payment_id' => $refund->getKey(),
                'reason' => $reason,
            ]);

            $newTotal = $alreadyRefunded + $amountMinor;
            $fresh->status = $newTotal >= (int) $fresh->amount_minor
                ? PaymentStatus::Refunded->value
                : PaymentStatus::PartiallyRefunded->value;
            $fresh->save();

            // Nakit iade çekmeceden ödenir.
            if ($fresh->methodEnum()->affectsCashDrawer() && $session !== null) {
                $this->cash->recordPaymentMovement($session, $refund, CashMovementType::Refund, $amountMinor, $actor, $reason);
            }

            $this->audit->log('payments.refunded', $fresh, null, [
                'order_id' => $locked->getKey(),
                'refund_payment_id' => $refund->getKey(),
                'amount_minor' => $amountMinor,
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $refund;
        });
    }

    /**
     * Adisyonun TÜM başarılı ödemelerini iade eder (eski /orders/{id}/refund
     * ucunun ADR-010 uyumlu hâli). Sipariş durumu applyRefundDelta ile
     * Refunded'a türetilir.
     *
     * @return array<int, Payment> açılan iade kayıtları
     */
    public function refundOrderFully(Order $order, string $reason, User $actor, ?int $expectedVersion = null): array
    {
        if ($order->statusEnum() !== \App\Modules\Orders\Enums\OrderStatus::Paid) {
            throw ValidationException::withMessages(['status' => ['Yalnız ödenmiş adisyon iade edilebilir.']]);
        }

        $payments = Payment::withoutTenancy()
            ->where('order_id', $order->getKey())
            ->where('kind', 'payment')
            ->whereIn('status', [PaymentStatus::Succeeded->value, PaymentStatus::PartiallyRefunded->value])
            ->orderBy('id')
            ->get();

        $refunds = [];

        foreach ($payments as $p) {
            $remaining = (int) $p->amount_minor - $p->refundedTotalMinor();

            if ($remaining > 0) {
                $refunds[] = $this->refund($p, $remaining, $reason, $actor, $expectedVersion);
                $expectedVersion = null; // sürüm ilk adımda doğrulandı
            }
        }

        return $refunds;
    }

    /* =========================================================
     |  Yardımcılar
     * ========================================================= */

    /** Adisyondaki bekleyen (terminalde) ödemelerin toplamı. */
    private function pendingTotalMinor(Order $order): int
    {
        return (int) Payment::withoutTenancy()
            ->where('order_id', $order->getKey())
            ->where('kind', 'payment')
            ->where('status', PaymentStatus::Pending->value)
            ->sum('amount_minor');
    }

    /** Nakit yuvarlama: kalan tutarı adım değerine yuvarlar (half-up). */
    private function applyCashRounding(Order $locked, User $actor): void
    {
        $step = max(1, (int) config('payments.cash_rounding_step_minor', 25));
        $remaining = max(0, (int) $locked->total_minor - (int) $locked->paid_minor);

        if ($remaining === 0 || $step === 1) {
            return;
        }

        $rounded = (int) (round($remaining / $step, 0, PHP_ROUND_HALF_UP) * $step);
        $delta = $rounded - $remaining;

        if ($delta === 0) {
            return;
        }

        $newRounding = (int) $locked->rounding_minor + $delta;
        $max = (int) config('payments.max_rounding_minor', 99);

        if (abs($newRounding) > $max) {
            return; // sınır aşılırsa yuvarlama sessizce uygulanmaz (tutar aynen kalır)
        }

        $this->orders->applyRounding($locked, $newRounding, $actor);
    }
}
