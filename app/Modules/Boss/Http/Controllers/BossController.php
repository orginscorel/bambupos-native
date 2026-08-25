<?php

declare(strict_types=1);

namespace App\Modules\Boss\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Boss\Services\BossService;
use App\Modules\Tenancy\Concerns\ScopesToBranch;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * YÖNETİM KOKPİTİ (BOSS) API'si. İzin: `boss.view` (patron/yönetici özeti).
 *
 * Dönem: `period` (day|week|month) VEYA açık `from`&`to` (Y-m-d). Şube kimliği
 * DAİMA BranchContext'ten çözülür — istekten gelmez; yönetici seçili şubesini,
 * sahip/müdür geneli/seçili şubeyi görür (ScopesToBranch). Tarihler şube saat
 * diliminde yorumlanır.
 */
final class BossController extends Controller
{
    use ScopesToBranch;

    public function __construct(
        private readonly BossService $service,
    ) {
    }

    /** Kokpit özeti (JSON). İzin: boss.view. */
    public function overview(Request $request): JsonResponse
    {
        abort_unless($request->user()->hasPermission('boss.view'), 403);

        $data = $request->validate([
            'period' => ['sometimes', Rule::in(['day', 'week', 'month'])],
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d'],
        ]);

        $branchId = $this->currentBranchId();
        $timezone = (string) ($this->branchContext()->currentBranch()?->timezone ?? config('app.timezone'));

        [$from, $to] = $this->resolveRange($data, $timezone);

        $overview = $this->service->overview($from, $to, $branchId);

        return response()->json(['data' => $overview]);
    }

    /**
     * Dönem çözümü: açık from/to verilmişse onu (kısmi verilirse eksik uç
     * bugüne düşer), yoksa period ön-ayarını (varsayılan: bugün) kullanır.
     * Ters aralık düzeltilir.
     *
     * @param  array<string, string>  $data
     * @return array{0: string, 1: string}  [from, to] (Y-m-d, şube tz)
     */
    private function resolveRange(array $data, string $timezone): array
    {
        $today = CarbonImmutable::now($timezone)->startOfDay();

        if (isset($data['from']) || isset($data['to'])) {
            $from = isset($data['from']) ? CarbonImmutable::parse($data['from'], $timezone)->startOfDay() : $today;
            $to = isset($data['to']) ? CarbonImmutable::parse($data['to'], $timezone)->startOfDay() : $today;
        } else {
            [$from, $to] = match ($data['period'] ?? 'day') {
                'week' => [$today->startOfWeek(), $today],
                'month' => [$today->startOfMonth(), $today],
                default => [$today, $today],
            };
        }

        if ($from->gt($to)) {
            [$from, $to] = [$to, $from];
        }

        return [$from->toDateString(), $to->toDateString()];
    }
}
