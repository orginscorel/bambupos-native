<?php

declare(strict_types=1);

namespace App\Modules\Delivery\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Delivery\Models\OrderDelivery;
use App\Modules\Delivery\Services\DeliveryService;
use App\Modules\Identity\Models\User;
use App\Modules\Orders\Enums\ServiceType;
use App\Modules\Orders\Models\Order;
use App\Modules\Tenancy\Concerns\ScopesToBranch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Panel (yönetici) TESLİMAT API'si. İzin: `delivery.view` panoyu görüntüle,
 * `delivery.manage` kurye ata / durum güncelle. Tüm sorgular tenant-scope'lu
 * (BelongsToTenant) + ŞUBE KAPSAMI'yla (BranchContext) süzülür; başka şubenin
 * teslimatı ne listelenir ne değiştirilir.
 */
class DeliveryController extends Controller
{
    use ScopesToBranch;

    public function __construct(
        private readonly DeliveryService $service,
    ) {
    }

    /** Teslimat panosu + atanabilir kurye listesi. İzin: delivery.view VEYA manage. */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('delivery.view') || $user->hasPermission('delivery.manage'), 403);

        $branchId = $this->currentBranchId();

        // Paket siparişler (şube kapsamlı) — her birine bir teslimat kaydı eşlik
        // eder; yoksa ilk erişimde üretilir (firstOrCreate).
        $orders = Order::query()
            ->where('service_type', ServiceType::Package->value)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->latest('id')
            ->get();

        foreach ($orders as $order) {
            $this->service->forOrder($order);
        }

        $status = $request->query('status');

        $deliveries = OrderDelivery::query()
            ->whereIn('order_id', $orders->modelKeys())
            ->when(is_string($status) && $status !== '', fn ($q) => $q->where('status', $status))
            ->with(['order', 'courier'])
            ->orderByRaw("FIELD(status, 'pending', 'assigned', 'on_the_way', 'delivered', 'failed')")
            ->latest('id')
            ->get()
            ->map(fn (OrderDelivery $d): array => $this->service->toDto($d))
            ->all();

        return response()->json([
            'deliveries' => $deliveries,
            'couriers' => $this->couriers($branchId),
        ]);
    }

    /** Kurye ata. İzin: delivery.manage. */
    public function assign(Request $request, Order $order): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('delivery.manage'), 403);
        $this->assertPackageInScope($order);

        $data = $request->validate([
            'courier_id' => ['required', 'integer'],
        ]);

        // Kurye geçerli kiracı + şube içinde aktif (insan) personel olmalı.
        $branchId = $this->currentBranchId();
        $courierOk = User::ofCurrentTenant()
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->whereKey($data['courier_id'])
            ->exists();
        abort_unless($courierOk, 422);

        $delivery = $this->service->assign(
            $this->service->forOrder($order),
            (int) $data['courier_id'],
            $user,
        );

        return response()->json(['delivery' => $this->service->toDto($delivery->fresh(['order', 'courier']))]);
    }

    /** Durum güncelle. İzin: delivery.manage. */
    public function status(Request $request, Order $order): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('delivery.manage'), 403);
        $this->assertPackageInScope($order);

        $data = $request->validate([
            'status' => ['required', Rule::in(['pending', 'assigned', 'on_the_way', 'delivered', 'failed'])],
        ]);

        $delivery = $this->service->setStatus($this->service->forOrder($order), $data['status']);

        return response()->json(['delivery' => $this->service->toDto($delivery->fresh(['order', 'courier']))]);
    }

    /** Teslimat bilgisini düzenle (adres/not/ücret). İzin: delivery.manage. */
    public function update(Request $request, Order $order): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasPermission('delivery.manage'), 403);
        $this->assertPackageInScope($order);

        $data = $request->validate([
            'address' => ['sometimes', 'string', 'max:400'],
            'note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'fee_minor' => ['sometimes', 'integer', 'min:0'],
        ]);

        $delivery = $this->service->forOrder($order);
        $delivery->fill($data);
        $delivery->save();

        return response()->json(['delivery' => $this->service->toDto($delivery->fresh(['order', 'courier']))]);
    }

    /**
     * Atanabilir kurye listesi: aktif (insan) personel; teslimat izni
     * (delivery.deliver) olanlar başa alınır. Şube kapsamlı.
     *
     * @return array<int, array{id:int, name:string}>
     */
    private function couriers(?int $branchId): array
    {
        return User::ofCurrentTenant()
            ->where('is_active', true)
            ->where('is_terminal', false)
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->orderBy('first_name')
            ->get(['id', 'name', 'first_name', 'position'])
            // Kurye izni olanlar önce (PHP 8 sort stabil → isim sırası korunur).
            ->sortByDesc(fn (User $u): int => $u->hasPermission('delivery.deliver') ? 1 : 0)
            ->values()
            ->map(fn (User $u): array => [
                'id' => (int) $u->getKey(),
                'name' => $u->name,
            ])
            ->all();
    }

    /**
     * Sipariş paket teslimatına uygun ve geçerli şube kapsamında değilse 404
     * (sızıntı yok). Order route-binding'i zaten kiracıya süzülüdür.
     */
    private function assertPackageInScope(Order $order): void
    {
        abort_unless($order->serviceTypeEnum() === ServiceType::Package, 404);

        $branchId = $this->currentBranchId();
        if ($branchId !== null
            && $order->branch_id !== null
            && (int) $order->branch_id !== $branchId) {
            abort(404);
        }
    }
}
