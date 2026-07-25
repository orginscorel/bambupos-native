<?php

namespace App\Modules\Kds\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kds\Services\KdsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * KDS okuma uçları (ADR-006: 3-5 sn cursor'lı polling).
 *
 * `updates` ucu değişiklik yoksa 204 (boş gövde) döner — sunucu maliyeti
 * tek indeksli MAX(id) sorgusudur; tam kuyruk YALNIZ değişiklik olduğunda
 * üretilir. Yanıtlar kişiye özel olduğundan sayfa-cache'lenmez.
 */
class KdsQueueController extends Controller
{
    public function __construct(private readonly KdsService $kds)
    {
    }

    /** Tam kuyruk (ilk yükleme / değişiklik sonrası). mode=runner → komi. */
    public function queue(Request $request): JsonResponse
    {
        $mode = (string) $request->query('mode', 'kitchen');
        $this->authorizeMode($request, $mode);

        $branchId = (int) $request->query('branch_id', 0);
        $lane = $this->laneOf($request);

        $payload = $mode === 'runner'
            ? $this->kds->runnerQueue($request->user(), $branchId)
            : $this->kds->kitchenQueue($request->user(), $branchId, $request->query('station'), $lane);

        return response()->json($payload, 200, ['Cache-Control' => 'no-store, private']);
    }

    /**
     * Cursor'lı delta yoklaması: cursor'dan yeni olay yoksa 204 + boş gövde,
     * varsa güncel kuyruk (istemci cursor'ı yanıtla günceller).
     */
    public function updates(Request $request): Response
    {
        $mode = (string) $request->query('mode', 'kitchen');
        $this->authorizeMode($request, $mode);

        $branchId = (int) $request->query('branch_id', 0);
        $cursor = (int) $request->query('cursor', 0);

        $latest = $this->kds->cursor($branchId);

        if ($latest <= $cursor) {
            return response()->noContent()->withHeaders([
                'X-Kds-Cursor' => (string) $latest,
                'Cache-Control' => 'no-store, private',
            ]);
        }

        return $this->queue($request);
    }

    /**
     * Ekran KULVARI (Mutfak/Barista) — istemciden gelir ama YALNIZCA kısıtlar
     * (kesişim; atanmış kapsamı asla genişletmez), bu yüzden güven sınırı
     * değildir. Geçersiz değer → null (kulvar kısıtı yok).
     */
    private function laneOf(Request $request): ?string
    {
        $lane = $request->query('lane');

        return in_array($lane, ['kitchen', 'barista'], true) ? $lane : null;
    }

    private function authorizeMode(Request $request, string $mode): void
    {
        $user = $request->user();

        if ($mode === 'runner') {
            abort_unless($user->hasPermission('kds.deliver'), 403);

            return;
        }

        abort_unless($user->hasPermission('kds.view'), 403);
    }
}
