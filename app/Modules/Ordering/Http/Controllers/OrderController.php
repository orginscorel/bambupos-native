<?php

namespace App\Modules\Ordering\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Identity\Services\AuditLogger;
use App\Modules\Ordering\Models\Order;
use App\Modules\Tenancy\Models\Branch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class OrderController extends Controller
{
    public function __construct(private readonly AuditLogger $audit)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->authorize('viewAny', Order::class);

        return response()->json(['orders' => Order::query()->latest('id')->paginate(50)]);
    }

    public function store(Request $request): JsonResponse
    {
        $this->authorize('create', Order::class);

        $data = $request->validate([
            'branch_id' => ['required', 'integer'],
            'total_minor' => ['sometimes', 'integer', 'min:0'],
        ]);

        // Branch global scope'lu: yabancı şube 422.
        $branch = Branch::query()->find($data['branch_id']);

        if ($branch === null) {
            throw ValidationException::withMessages(['branch_id' => ['Şube bulunamadı.']]);
        }

        $order = new Order(['total_minor' => $data['total_minor'] ?? 0]);
        $order->branch_id = $branch->id;
        $order->save();

        return response()->json(['order' => $order], 201);
    }

    public function show(Request $request, Order $order): JsonResponse
    {
        $this->authorize('view', $order);

        return response()->json(['order' => $order]);
    }

    public function cancel(Request $request, Order $order): JsonResponse
    {
        $this->authorize('cancel', $order);

        $old = $order->status;
        $order->update(['status' => 'cancelled']);

        $this->audit->log('orders.cancelled', $order, ['status' => $old], ['status' => 'cancelled']);

        return response()->json(['order' => $order]);
    }
}
