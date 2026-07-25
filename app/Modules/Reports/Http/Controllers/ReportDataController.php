<?php

namespace App\Modules\Reports\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Reports\Support\ReportFilters;
use App\Modules\Reports\Support\ReportRegistry;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Rapor verisi (JSON). Anahtar kapalı listeden (ReportRegistry) çözülür;
 * kiracı bağlamı ReportFilters içinde kurulur, istekten tenant sızmaz.
 * Bu uçtaki raporlar "küçük/anlık" sınıfındandır ve doğrudan üretilir;
 * dosya çıktıları (büyük işler) ExportController → queue'dan geçer (§23).
 */
class ReportDataController extends Controller
{
    public function show(Request $request, string $report): JsonResponse
    {
        abort_unless($request->user()->hasPermission('reports.view'), 403);
        abort_unless(ReportRegistry::exists($report), 404);

        $filters = ReportFilters::fromRequest($request);

        return response()->json([
            'report' => $report,
            'filters' => [
                'from' => $filters->from,
                'to' => $filters->to,
                'branch_id' => $filters->branchId,
                'timezone' => $filters->timezone,
            ],
            'data' => ReportRegistry::run($report, $filters),
        ]);
    }
}
