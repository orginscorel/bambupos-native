<?php

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\IdempotencyStore;
use App\Modules\Orders\Support\OrderPresenter;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Payments\Models\Payment;
use App\Modules\Payments\Providers\ProviderRegistry;
use App\Modules\Payments\Services\PaymentService;
use App\Modules\Payments\Support\PaymentPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Kasiyer ödeme API'si. Tüm sorgular tenant-scope'lu; mutasyonlar
 * PaymentService'te (transaction + kilit + sürüm + idempotency).
 */
class PaymentController extends Controller
{
    public function __construct(
        private readonly PaymentService $payments,
        private readonly IdempotencyStore $idempotency,
        private readonly ProviderRegistry $providers,
    ) {
    }

    /** Ödeme bekleyen açık adisyonlar (kasiyer ekranı; hesap isteyenler önce). */
    public function pendingOrders(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Payment::class);

        $query = Order::query()
            ->with(['table:id,name,number', 'items'])
            ->whereNotIn('status', [
                OrderStatus::Draft->value, OrderStatus::PendingApproval->value,
                ...OrderStatus::closedValues(),
            ]);

        if ($request->filled('branch_id')) {
            $query->where('branch_id', (int) $request->query('branch_id'));
        }

        if ($request->filled('q')) {
            $needle = '%'.str_replace(['%', '_'], ['\\%', '\\_'], (string) $request->query('q')).'%';
            $query->where(function ($w) use ($needle): void {
                $w->where('id', 'like', $needle)
                    ->orWhere('customer_name', 'like', $needle)
                    ->orWhereHas('table', fn ($t) => $t->where('name', 'like', $needle));
            });
        }

        $orders = $query->orderByRaw(
            "case when status = 'bill_requested' then 0 when status = 'partially_paid' then 1 else 2 end"
        )->orderByDesc('id')->limit(100)->get();

        return response()->json([
            'orders' => $orders->map(fn (Order $o): array => OrderPresenter::summary($o))->values()->all(),
        ]);
    }

    /** Adisyonun ödeme geçmişi. */
    public function index(Request $request, Order $order): JsonResponse
    {
        $this->authorize('viewAny', Payment::class);

        $payments = Payment::query()
            ->with('cashier:id,name')
            ->where('order_id', $order->getKey())
            ->orderBy('id')
            ->get();

        return response()->json([
            'order' => OrderPresenter::summary($order->load(['table:id,name,number', 'items'])),
            'payments' => $payments->map(fn (Payment $p): array => PaymentPresenter::payment($p))->values()->all(),
        ]);
    }

    /** Ödeme al (anında ya da terminal başlatma). Idempotency-Key desteklenir. */
    public function store(Request $request, Order $order): JsonResponse
    {
        $this->authorize('take', Payment::class);

        // Kiracı eşitliği (katman 2 — scope'tan bağımsız yeniden doğrulama).
        abort_unless((int) $order->tenant_id === (int) $request->user()->tenant_id, 404);

        $data = $request->validate([
            'method' => ['required', Rule::enum(PaymentMethod::class)],
            'amount_minor' => ['required', 'integer', 'min:1'],
            'tip_minor' => ['sometimes', 'integer', 'min:0', 'max:100000000'],
            'tendered_minor' => ['nullable', 'integer', 'min:0'],
            'note' => ['nullable', 'string', 'max:255'],
            'round' => ['sometimes', 'boolean'],
            'provider' => ['nullable', 'string', 'max:30'],
            'terminal_id' => ['nullable', 'string', 'max:60'],
            'cash_register_id' => ['nullable', 'integer'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        [$response, $status, $replayed] = $this->idempotency->run(
            (int) $order->tenant_id,
            $request->header('Idempotency-Key'),
            'payments.store',
            function () use ($order, $data, $request): array {
                $result = $this->payments->pay($order, $data, $request->user(), $data['expected_version'] ?? null);

                return [[
                    'payment' => PaymentPresenter::payment($result['payment']),
                    'provider_result' => $result['provider_result'] !== null ? [
                        'status' => $result['provider_result']->status,
                        'message' => $result['provider_result']->message,
                    ] : null,
                    'order' => $this->freshOrder($order),
                ], 201];
            },
        );

        return response()->json($response + ['replayed' => $replayed], $replayed ? 200 : $status);
    }

    /** Bekleyen terminal ödemesini sağlayıcıdan sorgula ve netleştir. */
    public function query(Request $request, Payment $payment): JsonResponse
    {
        $this->authorize('query', $payment);

        $result = $this->payments->queryAndSettle($payment, $request->user());

        return response()->json([
            'payment' => PaymentPresenter::payment($result['payment']),
            'provider_result' => $result['provider_result'] !== null ? [
                'status' => $result['provider_result']->status,
                'message' => $result['provider_result']->message,
            ] : null,
            'order' => $this->freshOrder($payment->order()->firstOrFail()),
        ]);
    }

    /** Ödeme iptali (void) — ayrı izin (payments.refund). */
    public function void(Request $request, Payment $payment): JsonResponse
    {
        $this->authorize('void', $payment);

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $voided = $this->payments->void($payment, $data['reason'], $request->user(), $data['expected_version'] ?? null);

        return response()->json([
            'payment' => PaymentPresenter::payment($voided),
            'order' => $this->freshOrder($payment->order()->firstOrFail()),
        ]);
    }

    /** Kısmi/tam iade — ayrı izin (payments.refund). */
    public function refund(Request $request, Payment $payment): JsonResponse
    {
        $this->authorize('refund', $payment);

        $data = $request->validate([
            'amount_minor' => ['required', 'integer', 'min:1'],
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $refund = $this->payments->refund($payment, (int) $data['amount_minor'], $data['reason'], $request->user(), $data['expected_version'] ?? null);

        return response()->json([
            'refund' => PaymentPresenter::payment($refund),
            'payment' => PaymentPresenter::payment($payment->fresh()),
            'order' => $this->freshOrder($payment->order()->firstOrFail()),
        ], 201);
    }

    /** Terminal durumu (kasiyer ekranı göstergesi). */
    public function terminalStatus(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Payment::class);

        $providerKey = (string) $request->query('provider', (string) config('payments.default_terminal_provider', 'mock'));

        if (! $this->providers->has($providerKey)) {
            return response()->json(['online' => false, 'message' => 'Bilinmeyen sağlayıcı.'], 422);
        }

        $status = $this->providers->get($providerKey)->getTerminalStatus($request->query('terminal_id'));

        return response()->json([
            'online' => $status->online,
            'terminal_id' => $status->terminalId,
            'message' => $status->message,
        ]);
    }

    /** @return array<string, mixed> */
    private function freshOrder(Order $order): array
    {
        $fresh = Order::query()
            ->with(['items.options', 'table:id,name,number'])
            ->findOrFail($order->getKey());

        return OrderPresenter::summary($fresh);
    }
}
