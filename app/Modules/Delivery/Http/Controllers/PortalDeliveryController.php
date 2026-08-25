<?php

declare(strict_types=1);

namespace App\Modules\Delivery\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Delivery\Models\OrderDelivery;
use App\Modules\Delivery\Services\DeliveryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Portal "Teslimatlarım" (kurye self-servis). Kurye YALNIZ kendine atanmış
 * aktif teslimatları görür ve durumunu ilerletir (on_the_way / delivered).
 * Oturum yeterlidir (delivery.deliver izinli kullanıcı). Başkasının teslimatına
 * erişim 404 (sızıntı yok). OrderDelivery route-binding'i kiracıya süzülüdür.
 */
class PortalDeliveryController extends Controller
{
    public function __construct(
        private readonly DeliveryService $service,
    ) {
    }

    /** Kuryeye atanmış AKTİF teslimatlar (assigned / on_the_way). */
    public function index(Request $request): JsonResponse
    {
        $userId = (int) $request->user()->getKey();

        $deliveries = OrderDelivery::query()
            ->where('courier_id', $userId)
            ->whereIn('status', ['assigned', 'on_the_way'])
            ->with(['order', 'courier'])
            ->orderByRaw("FIELD(status, 'assigned', 'on_the_way')")
            ->latest('id')
            ->get()
            ->map(fn (OrderDelivery $d): array => $this->service->toDto($d))
            ->all();

        return response()->json(['deliveries' => $deliveries]);
    }

    /**
     * Kendi teslimatının durumunu ilerlet (on_the_way | delivered). delivered →
     * delivered_at damgalanır + yöneticilere DeliveryDelivered bildirimi gider
     * (servis katmanı). Başkasının teslimatı 404.
     */
    public function updateStatus(Request $request, OrderDelivery $delivery): JsonResponse
    {
        $userId = (int) $request->user()->getKey();
        abort_unless((int) $delivery->courier_id === $userId, 404);

        $data = $request->validate([
            'status' => ['required', Rule::in(['on_the_way', 'delivered'])],
        ]);

        $delivery = $this->service->setStatus($delivery, $data['status']);

        return response()->json(['delivery' => $this->service->toDto($delivery->fresh(['order', 'courier']))]);
    }
}
