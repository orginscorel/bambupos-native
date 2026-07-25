<?php

namespace App\Modules\Reports\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reports\Services\DashboardService;
use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Panel açılış verisi. Her oturumlu panel kullanıcısı çağırabilir;
 * bölümler kullanıcının İZİNLERİNE göre sunucu tarafında süzülür —
 * izinsiz bölüm yanıtta hiç yer almaz (finans sızıntısı yok).
 */
class DashboardController extends Controller
{
    public function index(Request $request, DashboardService $service): JsonResponse
    {
        $today = ReportFilters::fromRequest($request, 'today');

        // Eğilim grafiği: son 14 gün (bugün dahil) — sabit, ayrı sorgu paramı yok.
        $trend = ReportFilters::fromArray([
            'tenant_id' => $today->tenantId,
            'branch_id' => $today->branchId,
            'timezone' => $today->timezone,
            'from' => \Carbon\CarbonImmutable::now($today->timezone)->subDays(13)->toDateString(),
            'to' => \Carbon\CarbonImmutable::now($today->timezone)->toDateString(),
        ]);

        return response()->json([
            'sections' => $service->build($request->user(), $today, $trend),
        ]);
    }
}
