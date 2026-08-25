<?php

namespace App\Modules\Shifts\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Shifts\Services\PerformanceService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Personel performans özeti (dengeli metrik seti; Orders'tan salt-okunur).
 * Satış/ciro içerdiği için staff.view ister.
 */
class PerformanceController extends Controller
{
    use \App\Modules\Tenancy\Concerns\ScopesToBranch;

    public function __construct(private readonly PerformanceService $performance)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        abort_unless(
            $user->hasPermission('staff.view') || $user->hasPermission('staff.manage'),
            403,
        );

        $data = $request->validate([
            'from' => ['required', 'date'],
            'to' => ['required', 'date', 'after:from'],
        ]);

        return response()->json([
            'metrics' => $this->performance->staffMetrics(
                CarbonImmutable::parse($data['from']),
                CarbonImmutable::parse($data['to']),
                // ŞUBE KAPSAMI: yönetici aktif seçili şubesinin performansını görür.
                $this->currentBranchId(),
            ),
        ]);
    }
}
