<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Portal\Services\PortalShiftService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Portal "Raporlarım": kişinin KENDİ bugün/bu-ay çalışılan saati + mola/tuvalet
 * dakikası + mesai geçmişi. Detaylı performans sonraki fazda.
 */
class PortalReportController extends Controller
{
    public function __construct(private readonly PortalShiftService $shifts)
    {
    }

    public function index(Request $request): JsonResponse
    {
        return response()->json($this->shifts->reports($request->user()));
    }
}
