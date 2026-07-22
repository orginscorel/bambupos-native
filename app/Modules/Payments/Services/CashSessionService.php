<?php

namespace App\Modules\Payments\Services;

use App\Modules\Identity\Models\User;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Orders\Models\Order;
use App\Modules\Payments\Enums\CashMovementType;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Payments\Models\CashMovement;
use App\Modules\Payments\Models\CashRegister;
use App\Modules\Payments\Models\CashSession;
use App\Modules\Payments\Models\Payment;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Kasa yönetimi (prompt §16): açılış → hareketler → sayım → kapanış (Z).
 *
 * - Kasa hareketleri DEĞİŞMEZ defterdir (CashMovement guard'ı); düzeltme
 *   yalnız ters kayıtla yapılır — sessiz geriye dönük değişiklik yok.
 * - Beklenen nakit tek kaynaktan (hareket defteri toplamı) hesaplanır.
 * - Aynı kasada aynı anda TEK açık oturum (satır kilidiyle garanti).
 */
class CashSessionService
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    /* ---------------- Oturum ---------------- */

    public function open(CashRegister $register, int $openingFloatMinor, User $actor): CashSession
    {
        if ($openingFloatMinor < 0) {
            throw ValidationException::withMessages(['opening_float_minor' => ['Açılış tutarı negatif olamaz.']]);
        }

        return DB::transaction(function () use ($register, $openingFloatMinor, $actor): CashSession {
            /** @var CashRegister $locked */
            $locked = CashRegister::withoutTenancy()->lockForUpdate()->findOrFail($register->getKey());

            $existing = CashSession::withoutTenancy()
                ->where('cash_register_id', $locked->getKey())
                ->where('status', 'open')
                ->first();

            if ($existing !== null) {
                throw ValidationException::withMessages(['register' => ['Bu kasada zaten açık bir oturum var (Z#'.$existing->z_number.').']]);
            }

            $zNumber = (int) CashSession::withoutTenancy()
                ->where('cash_register_id', $locked->getKey())
                ->max('z_number') + 1;

            $session = new CashSession(['opening_float_minor' => $openingFloatMinor]);
            $session->tenant_id = $locked->tenant_id;
            $session->branch_id = $locked->branch_id;
            $session->cash_register_id = $locked->getKey();
            $session->z_number = $zNumber;
            $session->status = 'open';
            $session->opened_by_id = $actor->getKey();
            $session->opened_at = now();
            $session->save();

            $this->writeMovement($session, CashMovementType::OpeningFloat, 'in', $openingFloatMinor, 'Açılış kasası', $actor);

            $this->audit->log('cash.session_opened', $session, null, [
                'register' => $locked->name,
                'z_number' => $zNumber,
                'opening_float_minor' => $openingFloatMinor,
                'performed_by' => $actor->getKey(),
            ]);

            return $session;
        });
    }

    /**
     * Kapanış: sayım → beklenen vs sayılan → fark → Z raporu DONDURULUR.
     */
    public function close(CashSession $session, int $countedCashMinor, ?string $note, User $actor): CashSession
    {
        if ($countedCashMinor < 0) {
            throw ValidationException::withMessages(['counted_cash_minor' => ['Sayılan tutar negatif olamaz.']]);
        }

        return DB::transaction(function () use ($session, $countedCashMinor, $note, $actor): CashSession {
            /** @var CashSession $locked */
            $locked = CashSession::withoutTenancy()->lockForUpdate()->findOrFail($session->getKey());

            if (! $locked->isOpen()) {
                throw ValidationException::withMessages(['session' => ['Oturum zaten kapalı.']]);
            }

            $expected = $locked->expectedCashMinor();
            $difference = $countedCashMinor - $expected;

            $locked->status = 'closed';
            $locked->closed_by_id = $actor->getKey();
            $locked->closed_at = now();
            $locked->expected_cash_minor = $expected;
            $locked->counted_cash_minor = $countedCashMinor;
            $locked->difference_minor = $difference;
            $locked->closing_note = $note;
            $locked->summary = $this->buildReport($locked, $expected, $countedCashMinor, $difference);
            $locked->save();

            $this->audit->log('cash.session_closed', $locked, null, [
                'z_number' => (int) $locked->z_number,
                'expected_cash_minor' => $expected,
                'counted_cash_minor' => $countedCashMinor,
                'difference_minor' => $difference,
                'performed_by' => $actor->getKey(),
            ]);

            return $locked;
        });
    }

    /* ---------------- Hareketler ---------------- */

    /** Elle hareket: nakit giriş/çıkış, masraf, avans. */
    public function addMovement(CashSession $session, CashMovementType $type, int $amountMinor, string $reason, User $actor): CashMovement
    {
        if (! in_array($type, CashMovementType::manualTypes(), true)) {
            throw ValidationException::withMessages(['type' => ['Bu hareket türü elle eklenemez.']]);
        }

        if ($amountMinor <= 0) {
            throw ValidationException::withMessages(['amount_minor' => ['Tutar pozitif olmalı.']]);
        }

        return DB::transaction(function () use ($session, $type, $amountMinor, $reason, $actor): CashMovement {
            $locked = $this->lockedOpenSession($session);

            $movement = $this->writeMovement($locked, $type, $type->direction(), $amountMinor, $reason, $actor);

            $this->audit->log('cash.movement_added', $movement, null, [
                'session_id' => $locked->getKey(),
                'type' => $type->value,
                'amount_minor' => $amountMinor,
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $movement;
        });
    }

    /**
     * TERS KAYIT: hatalı hareket silinmez/değiştirilmez; yönü ters yeni
     * kayıt açılır ve iki kayıt birbirine bağlanır (denetim izi).
     */
    public function reverse(CashMovement $movement, string $reason, User $actor): CashMovement
    {
        return DB::transaction(function () use ($movement, $reason, $actor): CashMovement {
            /** @var CashMovement $fresh */
            $fresh = CashMovement::withoutTenancy()->lockForUpdate()->findOrFail($movement->getKey());

            if ($fresh->reversed_by_id !== null) {
                throw ValidationException::withMessages(['movement' => ['Bu hareket zaten ters kayıtla düzeltilmiş.']]);
            }

            if ($fresh->type === CashMovementType::OpeningFloat->value) {
                throw ValidationException::withMessages(['movement' => ['Açılış kaydı ters kayıtla düzeltilemez; oturumu kapatın.']]);
            }

            $session = $this->lockedOpenSession(
                CashSession::withoutTenancy()->findOrFail($fresh->cash_session_id),
            );

            $reversal = new CashMovement([
                'type' => CashMovementType::Correction->value,
                'direction' => $fresh->direction === 'in' ? 'out' : 'in',
                'amount_minor' => (int) $fresh->amount_minor,
                'reason' => 'Ters kayıt: '.$reason,
            ]);
            $reversal->tenant_id = $fresh->tenant_id;
            $reversal->branch_id = $fresh->branch_id;
            $reversal->cash_session_id = $session->getKey();
            $reversal->user_id = $actor->getKey();
            $reversal->reverses_id = $fresh->getKey();
            $reversal->save();

            $fresh->reversed_by_id = $reversal->getKey();
            $fresh->save(); // guard yalnız bu alana izin verir

            $this->audit->log('cash.movement_reversed', $fresh, null, [
                'reversal_id' => $reversal->getKey(),
                'reason' => $reason,
                'performed_by' => $actor->getKey(),
            ]);

            return $reversal;
        });
    }

    /** Sistem hareketi: nakit tahsilat / nakit iade (PaymentService yazar). */
    public function recordPaymentMovement(CashSession $session, Payment $payment, CashMovementType $type, int $amountMinor, ?User $actor, ?string $reason = null): CashMovement
    {
        $movement = $this->writeMovement(
            $session,
            $type,
            $type->direction(),
            $amountMinor,
            $reason ?? ($type === CashMovementType::Payment ? 'Nakit tahsilat #'.$payment->order_id : 'Nakit iade #'.$payment->order_id),
            $actor,
            $payment,
        );

        return $movement;
    }

    /** Void edilen nakit ödemenin çekmece çıkışı (ters kayıt biçiminde). */
    public function recordPaymentReversal(Payment $payment, ?User $actor, string $reason): ?CashMovement
    {
        $original = CashMovement::withoutTenancy()
            ->where('payment_id', $payment->getKey())
            ->where('type', CashMovementType::Payment->value)
            ->whereNull('reversed_by_id')
            ->first();

        if ($original === null) {
            return null; // oturumsuz alınmış nakit — çekmece izi yok
        }

        $session = CashSession::withoutTenancy()->find($original->cash_session_id);

        if ($session === null || ! $session->isOpen()) {
            return null; // oturum kapandıysa düzeltme yeni oturumda elle yapılır
        }

        $reversal = new CashMovement([
            'type' => CashMovementType::Correction->value,
            'direction' => 'out',
            'amount_minor' => (int) $original->amount_minor,
            'reason' => 'Ödeme void: '.$reason,
        ]);
        $reversal->tenant_id = $original->tenant_id;
        $reversal->branch_id = $original->branch_id;
        $reversal->cash_session_id = $session->getKey();
        $reversal->user_id = $actor?->getKey();
        $reversal->reverses_id = $original->getKey();
        $reversal->save();

        $original->reversed_by_id = $reversal->getKey();
        $original->save();

        return $reversal;
    }

    /* ---------------- Ödeme ↔ oturum eşleme ---------------- */

    /**
     * Ödemenin bağlanacağı açık oturum: istenen kasa verilmişse onun açık
     * oturumu; verilmemişse şubede TEK açık oturum varsa o (belirsizlikte
     * null — ödeme oturumsuz kalır, Z dışı raporlanır).
     */
    public function resolveOpenSession(Order $order, ?int $registerId): ?CashSession
    {
        $query = CashSession::withoutTenancy()
            ->where('tenant_id', $order->tenant_id)
            ->where('branch_id', $order->branch_id)
            ->where('status', 'open');

        if ($registerId !== null) {
            return $query->where('cash_register_id', $registerId)->first();
        }

        $open = $query->limit(2)->get();

        return $open->count() === 1 ? $open->first() : null;
    }

    /* ---------------- X/Z raporu ---------------- */

    /**
     * Rapor verisi: açık oturumda CANLI (X), kapalı oturumda DONDURULMUŞ
     * `summary` (Z) döner.
     *
     * @return array<string, mixed>
     */
    public function report(CashSession $session): array
    {
        if (! $session->isOpen() && is_array($session->summary)) {
            return $session->summary;
        }

        $expected = $session->expectedCashMinor();

        return $this->buildReport(
            $session,
            $expected,
            $session->counted_cash_minor,
            $session->counted_cash_minor !== null ? $session->counted_cash_minor - $expected : null,
        );
    }

    /** @return array<string, mixed> */
    private function buildReport(CashSession $session, int $expected, ?int $counted, ?int $difference): array
    {
        $payments = Payment::withoutTenancy()
            ->where('cash_session_id', $session->getKey())
            ->get();

        $collected = $payments->where('kind', 'payment')
            ->filter(fn (Payment $p) => $p->statusEnum()->countsAsCollected());
        $refunds = $payments->where('kind', 'refund')
            ->where('status', PaymentStatus::Succeeded->value);
        $voids = $payments->where('kind', 'payment')
            ->where('status', PaymentStatus::Cancelled->value);

        // Yöntem kırılımı (tahsilat - o yöntemin iadesi = net).
        $byMethod = [];

        foreach (PaymentMethod::cases() as $method) {
            $in = (int) $collected->where('method', $method->value)->sum('amount_minor');
            $out = (int) $refunds->where('method', $method->value)->sum('amount_minor');
            $count = $collected->where('method', $method->value)->count();

            if ($in === 0 && $out === 0) {
                continue;
            }

            $byMethod[] = [
                'method' => $method->value,
                'label' => $method->label(),
                'count' => $count,
                'collected_minor' => $in,
                'refunded_minor' => $out,
                'net_minor' => $in - $out,
            ];
        }

        // Hareket kırılımı.
        $movements = $session->movements()->get();
        $movementTotals = [];

        foreach (CashMovementType::cases() as $type) {
            $sum = (int) $movements->where('type', $type->value)->sum('amount_minor');

            if ($sum > 0) {
                $movementTotals[] = [
                    'type' => $type->value,
                    'label' => $type->label(),
                    'direction' => $type->direction(),
                    'total_minor' => $sum,
                    'count' => $movements->where('type', $type->value)->count(),
                ];
            }
        }

        // Oturuma bağlı ödemelerin adisyonlarından indirim/ikram toplamları.
        $orderIds = $payments->pluck('order_id')->unique()->values();
        $orders = $orderIds->isEmpty()
            ? collect()
            : Order::withoutTenancy()->whereIn('id', $orderIds)->get();

        return [
            'session_id' => $session->getKey(),
            'z_number' => (int) $session->z_number,
            'status' => (string) $session->status,
            'register_id' => (int) $session->cash_register_id,
            'opened_at' => $session->opened_at?->toIso8601String(),
            'closed_at' => $session->closed_at?->toIso8601String(),
            'opening_float_minor' => (int) $session->opening_float_minor,
            'expected_cash_minor' => $expected,
            'counted_cash_minor' => $counted,
            'difference_minor' => $difference,
            'payments_total_minor' => (int) $collected->sum('amount_minor'),
            'payments_count' => $collected->count(),
            'refunds_total_minor' => (int) $refunds->sum('amount_minor'),
            'refunds_count' => $refunds->count(),
            'voids_total_minor' => (int) $voids->sum('amount_minor'),
            'voids_count' => $voids->count(),
            'tips_total_minor' => (int) $collected->sum('tip_minor'),
            'discounts_total_minor' => (int) $orders->sum('discount_minor'),
            'comps_total_minor' => (int) $orders->sum('comp_total_minor'),
            'service_charges_total_minor' => (int) $orders->sum('service_charge_minor'),
            'by_method' => $byMethod,
            'movements' => $movementTotals,
        ];
    }

    /* ---------------- İç yardımcılar ---------------- */

    private function lockedOpenSession(CashSession $session): CashSession
    {
        /** @var CashSession $locked */
        $locked = CashSession::withoutTenancy()->lockForUpdate()->findOrFail($session->getKey());

        if (! $locked->isOpen()) {
            throw ValidationException::withMessages(['session' => ['Oturum kapalı; hareket eklenemez.']]);
        }

        return $locked;
    }

    private function writeMovement(CashSession $session, CashMovementType $type, string $direction, int $amountMinor, ?string $reason, ?User $actor, ?Payment $payment = null): CashMovement
    {
        $movement = new CashMovement([
            'type' => $type->value,
            'direction' => $direction,
            'amount_minor' => $amountMinor,
            'reason' => $reason,
        ]);
        $movement->tenant_id = $session->tenant_id;
        $movement->branch_id = $session->branch_id;
        $movement->cash_session_id = $session->getKey();
        $movement->payment_id = $payment?->getKey();
        $movement->user_id = $actor?->getKey();
        $movement->save();

        return $movement;
    }
}
