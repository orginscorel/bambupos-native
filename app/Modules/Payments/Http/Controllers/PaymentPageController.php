<?php

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Payments\Enums\CashMovementType;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Enums\PaymentStatus;
use App\Modules\Payments\Models\CashSession;
use App\Modules\Payments\Models\Payment;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Kasiyer/kasa ekranları (Inertia). Enum sözlükleri PHP'den prop olarak
 * gider (tek kaynak); veri /api/v1 uçlarından yüklenir.
 */
class PaymentPageController extends Controller
{
    public function cashier(): Response
    {
        $this->authorize('viewAny', Payment::class);

        return Inertia::render('Panel/Payments/Cashier', $this->meta());
    }

    public function cashDesk(): Response
    {
        $this->authorize('viewAny', CashSession::class);

        return Inertia::render('Panel/Payments/CashDesk', $this->meta());
    }

    public function zReport(CashSession $session): Response
    {
        $this->authorize('view', $session);

        return Inertia::render('Panel/Payments/ZReport', $this->meta() + [
            'sessionId' => $session->getKey(),
        ]);
    }

    /** @return array<string, mixed> */
    private function meta(): array
    {
        return [
            'paymentMethods' => PaymentMethod::options(),
            'paymentStatuses' => PaymentStatus::options(),
            'movementTypes' => CashMovementType::manualOptions(),
            'cashRoundingStep' => (int) config('payments.cash_rounding_step_minor', 25),
            'canRefund' => (bool) auth()->user()?->hasPermission('payments.refund'),
            // Kasada indirim uygulanabilsin (hazır tanımlar) — adisyon ekranına gitmeden.
            'canDiscount' => (bool) auth()->user()?->hasPermission('orders.discount'),
            'canCashManage' => (bool) auth()->user()?->hasPermission('cash.close'),
            'canCashView' => (bool) auth()->user()?->hasPermission('cash.view'),
        ];
    }
}
