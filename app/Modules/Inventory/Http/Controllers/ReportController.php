<?php

namespace App\Modules\Inventory\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Services\ReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * Stok raporu uçları (§17 madde 7) — dönem mutabakatı + gün sonu.
 * Salt okuma (stock.view yeterli); para/miktar sunucuda hesaplanır.
 */
class ReportController extends Controller
{
    public function __construct(private readonly ReportService $reports)
    {
    }

    /**
     * Dönem mutabakat raporu. `preset=day|month` VEYA `from`/`to` (YYYY-MM-DD).
     * Tarihler şube tz'sinden bağımsız gün sınırında UTC'ye hizalanır.
     */
    public function period(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockItem::class);

        [$from, $to] = $this->range($request);

        return response()->json(
            $this->reports->period((int) $request->user()->tenant_id, $from, $to),
        );
    }

    /** Gün sonu: seçilen günde stoktan düşen kalemler. */
    public function dayEnd(Request $request): JsonResponse
    {
        $this->authorize('viewAny', StockItem::class);

        $day = $this->parseDate($request->query('date')) ?? Carbon::now();

        return response()->json([
            'date' => $day->toDateString(),
            'items' => $this->reports->dayEnd((int) $request->user()->tenant_id, $day),
        ]);
    }

    /** @return array{0: Carbon, 1: Carbon} */
    private function range(Request $request): array
    {
        $preset = (string) $request->query('preset', '');

        if ($preset === 'month') {
            $anchor = $this->parseDate($request->query('date')) ?? Carbon::now();

            return [$anchor->copy()->startOfMonth(), $anchor->copy()->endOfMonth()];
        }

        if ($preset === 'day' || ($request->query('from') === null && $request->query('to') === null)) {
            $anchor = $this->parseDate($request->query('date')) ?? Carbon::now();

            return [$anchor->copy()->startOfDay(), $anchor->copy()->endOfDay()];
        }

        $from = ($this->parseDate($request->query('from')) ?? Carbon::now())->startOfDay();
        $to = ($this->parseDate($request->query('to')) ?? Carbon::now())->endOfDay();

        if ($to->lessThan($from)) {
            [$from, $to] = [$to->copy()->startOfDay(), $from->copy()->endOfDay()];
        }

        return [$from, $to];
    }

    private function parseDate(mixed $value): ?Carbon
    {
        if (! is_string($value) || $value === '') {
            return null;
        }

        try {
            return Carbon::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }
}
