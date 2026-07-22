<?php

namespace App\Modules\Orders\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Venue\Enums\TableStatus;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Garson ekranları (Inertia sayfaları). Enum sözlükleri PHP'den prop
 * olarak gider (tek kaynak); veri /api/v1/orders uçlarından yüklenir.
 */
class OrderPageController extends Controller
{
    public function board(Request $request): Response
    {
        $this->authorize('viewAny', Order::class);

        return Inertia::render('Panel/Orders/Board', $this->meta());
    }

    public function detail(Request $request, Order $order): Response
    {
        $this->authorize('view', $order);

        return Inertia::render('Panel/Orders/Detail', $this->meta() + [
            'orderId' => $order->getKey(),
        ]);
    }

    /** @return array<string, mixed> */
    private function meta(): array
    {
        return [
            'orderStatuses' => OrderStatus::options(),
            'itemStatuses' => OrderItemStatus::options(),
            'channels' => OrderChannel::options(),
            'tableStatuses' => TableStatus::options(),
            'discountApprovalPercent' => (float) config('orders.discount_approval_threshold_percent', 10),
        ];
    }
}
