<?php

namespace App\Modules\Kds\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kds\Services\KdsService;
use App\Modules\Kds\Support\KdsPresenter;
use App\Modules\Orders\Enums\OrderItemStatus;
use App\Modules\Orders\Models\Order;
use App\Modules\Orders\Models\OrderItem;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * KDS eylem uçları. Model binding tenant-scope'ludur (yabancı kalem 404).
 * Sürüm çakışması OrderService çekirdeğinden 409 döner; ekran bunu
 * "çakışma uyarısı + tazeleme" olarak işler (prompt §12.4).
 *
 * Yanıtlarda FİNANSAL ALAN YOKTUR (KdsPresenter — prompt §20).
 */
class KdsActionController extends Controller
{
    public function __construct(
        private readonly KdsService $kds,
        private readonly KdsPresenter $presenter,
    ) {
    }

    /** Kalem durumu: accepted / preparing / ready / served (yalnız ileri). */
    public function itemStatus(Request $request, OrderItem $item): JsonResponse
    {
        $data = $request->validate([
            'to' => ['required', Rule::in(['accepted', 'preparing', 'ready', 'served'])],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $to = OrderItemStatus::from($data['to']);
        $user = $request->user();

        // served = komi/servis yetkisi; mutfak akışı kds.view.
        if ($to === OrderItemStatus::Served) {
            abort_unless($user->hasPermission('kds.deliver'), 403);
        } else {
            abort_unless($user->hasPermission('kds.view'), 403);
        }

        $item = $this->kds->advanceItem($user, $item, $to, $data['expected_version'] ?? null);

        return response()->json(['item' => $this->presenter->item($item->fresh(['options', 'product.allergens']), null)]);
    }

    /** Siparişin bu istasyondaki tüm bekleyen kalemleri → HAZIR. */
    public function stationReady(Request $request, Order $order): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.view'), 403);

        $data = $request->validate([
            'station' => ['nullable', 'string', 'max:40'],
            'lane' => ['nullable', Rule::in(['kitchen', 'barista'])],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $order = $this->kds->markStationReady(
            $request->user(),
            $order,
            $data['station'] ?? null,
            $data['expected_version'] ?? null,
            $data['lane'] ?? null,
        );

        return response()->json(['order_id' => $order->getKey(), 'version' => (int) $order->version]);
    }

    /** Yanlış işareti geri al: ready→preparing (mutfak), served→ready (komi). */
    public function undo(Request $request, OrderItem $item): JsonResponse
    {
        $user = $request->user();

        if ($item->statusEnum() === OrderItemStatus::Served) {
            abort_unless($user->hasPermission('kds.deliver'), 403);
        } else {
            abort_unless($user->hasPermission('kds.view'), 403);
        }

        $data = $request->validate(['expected_version' => ['nullable', 'integer']]);

        $item = $this->kds->undoItem($user, $item, $data['expected_version'] ?? null);

        return response()->json(['item' => $this->presenter->item($item->fresh(['options', 'product.allergens']), null)]);
    }

    /** İstasyon transferi (hazırlanmadan önce başka kuyruğa taşı). */
    public function transfer(Request $request, OrderItem $item): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.view'), 403);

        $data = $request->validate([
            'station' => ['required', 'string', 'max:40'],
            'expected_version' => ['nullable', 'integer'],
        ]);

        $item = $this->kds->transferItem($request->user(), $item, $data['station'], $data['expected_version'] ?? null);

        return response()->json(['item' => $this->presenter->item($item->fresh(['options', 'product.allergens']), null)]);
    }

    /** Komi: teslim aldım. */
    public function pickup(Request $request, OrderItem $item): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.deliver'), 403);

        $pickup = $this->kds->pickup($request->user(), $item);

        return response()->json([
            'picked_up_at' => $pickup->created_at?->toIso8601String(),
            'picked_up_by' => $pickup->user?->name,
        ], 201);
    }

    /** Komi: teslim işaretini geri al. */
    public function pickupUndo(Request $request, OrderItem $item): JsonResponse
    {
        abort_unless($request->user()->hasPermission('kds.deliver'), 403);

        $this->kds->undoPickup($request->user(), $item);

        return response()->json(['ok' => true]);
    }
}
