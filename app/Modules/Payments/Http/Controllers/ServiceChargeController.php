<?php

namespace App\Modules\Payments\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Services\OrderService;
use App\Modules\Orders\Support\OrderPresenter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Servis bedeli (prompt §15): adisyon toplamına yüzde/sabit ek.
 * Hesap OrderService'te (tutar otoritesi tek yerde — ADR-007).
 */
class ServiceChargeController extends Controller
{
    public function __construct(private readonly OrderService $orders)
    {
    }

    public function store(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $data = $request->validate([
            'type' => ['required', Rule::in(['percent', 'amount'])],
            'value' => ['required', 'numeric', 'gt:0'],
            'reason' => ['nullable', 'string', 'max:255'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $this->orders->applyServiceCharge($order, [
            'type' => $data['type'],
            'value' => $data['type'] === 'percent' ? (float) $data['value'] : (int) $data['value'],
            'reason' => $data['reason'] ?? null,
        ], $request->user(), $data['expected_version'] ?? null);

        return response()->json(['order' => $this->fresh($order)]);
    }

    public function destroy(Request $request, Order $order): JsonResponse
    {
        $this->authorize('update', $order);

        $this->orders->applyServiceCharge($order, null, $request->user(), $this->expectedVersion($request));

        return response()->json(['order' => $this->fresh($order)]);
    }

    /** @return array<string, mixed> */
    private function fresh(Order $order): array
    {
        return OrderPresenter::summary(
            Order::query()->with(['items', 'table:id,name,number'])->findOrFail($order->getKey()),
        );
    }

    private function expectedVersion(Request $request): ?int
    {
        $v = $request->input('expected_version');

        return $v === null || $v === '' ? null : (int) $v;
    }
}
