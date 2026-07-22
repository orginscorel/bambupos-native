<?php

namespace App\Modules\Kds\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Kds\Services\KdsService;
use App\Modules\Kds\Services\StationRegistry;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderItemStatus;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * KDS Inertia sayfaları: /panel/mutfak (mutfak+bar) ve /panel/komi.
 * Yalnız OPERASYON meta'sı gider — fiyat/ciro yok (prompt §20).
 */
class KdsPageController extends Controller
{
    public function __construct(
        private readonly StationRegistry $stations,
        private readonly KdsService $kds,
    ) {
    }

    /** Mutfak/bar ekranı. Bar = aynı ekran, ?istasyon=bar süzgeci. */
    public function kitchen(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('kds.view'), 403);

        return Inertia::render('Panel/Kds/Kitchen', $this->meta($request) + [
            'initialStation' => (string) $request->query('istasyon', ''),
        ]);
    }

    /** Komi ekranı: hazır ürünler → teslim aldım / masaya götürdüm. */
    public function runner(Request $request): Response
    {
        abort_unless($request->user()->hasPermission('kds.deliver'), 403);

        return Inertia::render('Panel/Kds/Runner', $this->meta($request));
    }

    /** @return array<string, mixed> */
    private function meta(Request $request): array
    {
        $user = $request->user();

        return [
            'stations' => $this->stations->all()->all(),
            'allowedStations' => $this->kds->allowedStations($user),
            'itemStatuses' => OrderItemStatus::options(),
            'channels' => OrderChannel::options(),
            'kdsConfig' => [
                'poll_interval_seconds' => (int) config('kds.poll_interval_seconds', 4),
                'default_prep_minutes' => (int) config('kds.default_prep_minutes', 15),
                'late_ratio' => (float) config('kds.late_ratio', 1.5),
                'unassigned_key' => (string) config('kds.unassigned_key', '_none'),
            ],
            'canManageStations' => $user->hasPermission('kds.manage'),
            'canDeliver' => $user->hasPermission('kds.deliver'),
        ];
    }
}
