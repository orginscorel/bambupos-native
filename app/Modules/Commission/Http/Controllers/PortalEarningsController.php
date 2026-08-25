<?php

declare(strict_types=1);

namespace App\Modules\Commission\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Commission\Services\CommissionService;
use App\Modules\Settings\Support\Features;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Portal "Kazancım": kişinin KENDİ dönemsel prim/kazanç özeti. Auth
 * kullanıcının KENDİ verisi (tenant + kişi bazlı; izin YOK, oturum yeter).
 * Prim özelliği (feature: commission) kapalıysa boş/uygun yanıt döner —
 * kapalı = veri sızmaz.
 */
class PortalEarningsController extends Controller
{
    public function __construct(
        private readonly CommissionService $service,
    ) {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'period' => ['nullable', Rule::in(['day', 'week', 'month'])],
        ]);
        $period = $data['period'] ?? 'week';

        // Prim özelliği kapalıysa: özet gösterilmez (enabled = false → boş yanıt).
        if (! Features::enabled((int) $user->tenant_id, 'commission')) {
            return response()->json([
                'enabled' => false,
                'period' => $period,
            ]);
        }

        [$from, $to] = $this->range($period);

        $summary = $this->service->forUser($user, $from, $to);

        return response()->json([
            'enabled' => true,
            'period' => $period,
            'from' => $from->toIso8601String(),
            'to' => $to->toIso8601String(),
            'sales_minor' => $summary['sales_minor'],
            'order_count' => $summary['order_count'],
            'commission_minor' => $summary['commission_minor'],
            'target_minor' => $summary['target_minor'],
            'target_met' => $summary['target_met'],
            'worked_min' => $summary['worked_min'],
            'scheme_name' => $summary['scheme']['name'] ?? null,
        ]);
    }

    /**
     * Portal dönem aralığı [from, to) — PortalPerformanceService ile aynı:
     * app timezone, hafta Pazartesi başlar.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    private function range(string $period): array
    {
        $now = Carbon::now(config('app.timezone'))->locale('tr');

        return match ($period) {
            'day' => [
                $from = $now->copy()->startOfDay(),
                $from->copy()->addDay(),
            ],
            'month' => [
                $from = $now->copy()->startOfMonth(),
                $from->copy()->addMonth(),
            ],
            default => [ // week
                $from = $now->copy()->startOfWeek(Carbon::MONDAY)->startOfDay(),
                $from->copy()->addDays(7),
            ],
        };
    }
}
