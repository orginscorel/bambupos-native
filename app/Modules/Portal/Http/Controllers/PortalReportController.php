<?php

namespace App\Modules\Portal\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Portal\Services\PortalPerformanceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Portal "Raporlarım": kişinin KENDİ dönemsel performansı — çalışılan saat +
 * mola/tuvalet + üretim/servis akışı (ready/pickup/served) + sipariş özeti.
 * Auth kullanıcının KENDİ verisi; tenant + kişi bazlı (izin YOK, oturum yeter).
 */
class PortalReportController extends Controller
{
    public function __construct(private readonly PortalPerformanceService $performance)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'period' => ['nullable', Rule::in(['day', 'week', 'month'])],
        ]);

        return response()->json(
            $this->performance->forUser($request->user(), $data['period'] ?? 'week')
        );
    }
}
