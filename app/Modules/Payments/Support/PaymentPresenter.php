<?php

namespace App\Modules\Payments\Support;

use App\Modules\Catalog\Support\Money;
use App\Modules\Payments\Models\CashMovement;
use App\Modules\Payments\Models\CashRegister;
use App\Modules\Payments\Models\CashSession;
use App\Modules\Payments\Models\Payment;

/** Ödeme/kasa JSON sunumu (tutarlar minor + biçimli — ADR-007). */
final class PaymentPresenter
{
    /** @return array<string, mixed> */
    public static function payment(Payment $payment): array
    {
        $status = $payment->statusEnum();
        $method = $payment->methodEnum();

        return [
            'id' => $payment->id,
            'order_id' => $payment->order_id,
            'reference' => $payment->reference,
            'kind' => $payment->kind,
            'refund_of_id' => $payment->refund_of_id,
            'method' => $method->value,
            'method_label' => $method->label(),
            'method_icon' => $method->icon(),
            'status' => $status->value,
            'status_label' => $status->label(),
            'status_icon' => $status->icon(),
            'status_variant' => $status->variant(),
            'amount_minor' => (int) $payment->amount_minor,
            'amount_display' => Money::toDecimalString((int) $payment->amount_minor),
            'tip_minor' => (int) $payment->tip_minor,
            'tendered_minor' => $payment->tendered_minor !== null ? (int) $payment->tendered_minor : null,
            'change_minor' => (int) $payment->change_minor,
            'currency' => $payment->currency,
            'provider' => $payment->provider,
            'provider_txn_id' => $payment->provider_txn_id,
            'terminal_id' => $payment->terminal_id,
            'cash_session_id' => $payment->cash_session_id,
            'cashier' => $payment->cashier?->name,
            'reason' => $payment->reason,
            'note' => $payment->note,
            'suspect' => (bool) $payment->suspect,
            'suspect_reason' => $payment->suspect_reason,
            'refunded_total_minor' => $payment->kind === 'payment' ? $payment->refundedTotalMinor() : 0,
            'paid_at' => $payment->paid_at?->toIso8601String(),
            'created_at' => $payment->created_at?->toIso8601String(),
        ];
    }

    /** @return array<string, mixed> */
    public static function register(CashRegister $register, ?CashSession $openSession = null): array
    {
        return [
            'id' => $register->id,
            'branch_id' => $register->branch_id,
            'name' => $register->name,
            'is_active' => (bool) $register->is_active,
            'open_session' => $openSession !== null ? self::session($openSession) : null,
        ];
    }

    /** @return array<string, mixed> */
    public static function session(CashSession $session): array
    {
        return [
            'id' => $session->id,
            'cash_register_id' => $session->cash_register_id,
            'register_name' => $session->register?->name,
            'branch_id' => $session->branch_id,
            'z_number' => (int) $session->z_number,
            'status' => (string) $session->status,
            'opening_float_minor' => (int) $session->opening_float_minor,
            'opened_by' => $session->openedBy?->name,
            'opened_at' => $session->opened_at?->toIso8601String(),
            'closed_by' => $session->closedBy?->name,
            'closed_at' => $session->closed_at?->toIso8601String(),
            'expected_cash_minor' => $session->expected_cash_minor !== null ? (int) $session->expected_cash_minor : null,
            'counted_cash_minor' => $session->counted_cash_minor !== null ? (int) $session->counted_cash_minor : null,
            'difference_minor' => $session->difference_minor !== null ? (int) $session->difference_minor : null,
            'closing_note' => $session->closing_note,
        ];
    }

    /** @return array<string, mixed> */
    public static function movement(CashMovement $movement): array
    {
        $type = $movement->typeEnum();

        return [
            'id' => $movement->id,
            'type' => $type->value,
            'type_label' => $type->label(),
            'direction' => (string) $movement->direction,
            'amount_minor' => (int) $movement->amount_minor,
            'amount_display' => Money::toDecimalString((int) $movement->amount_minor),
            'reason' => $movement->reason,
            'payment_id' => $movement->payment_id,
            'user' => $movement->user?->name,
            'reverses_id' => $movement->reverses_id,
            'reversed_by_id' => $movement->reversed_by_id,
            'created_at' => $movement->created_at?->toIso8601String(),
        ];
    }
}
