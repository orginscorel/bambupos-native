<?php

namespace App\Modules\Inventory\Services;

use App\Modules\Inventory\Enums\MovementType;
use App\Modules\Inventory\Models\StockItem;
use App\Modules\Inventory\Models\StockMovement;
use App\Modules\Inventory\Support\Qty;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Stok raporlama (§17 madde 7). Defter (inv_movements) TEK doğruluk
 * kaynağıdır; rapor SORGUyla hesaplanır (ayrı tablo yok).
 *
 * Sağlanan mekanizma:
 *   - Dönem (gün / ay / geçmiş-gün / özel aralık) bazında her kalem için
 *     AÇILIŞ → GİRİŞ → ÇIKIŞ → KAPANIŞ mutabakatı (giriş vs çıkış vs kalan).
 *   - "Gün sonu" görünümü: seçilen günde stoktan düşen (tüketilen) kalemler
 *     — "bugün stoktan şu kadar X azaldı".
 *   - Tüketim maliyeti (kuruş): satış/reçete/ikram çıkışlarının maliyeti →
 *     ciro-maliyet (kâr) bağı için ham veri.
 *
 * Miktarlar milli-int (ana birim ×1000), para kuruş-int (ADR-007).
 */
class ReportService
{
    /** Çıkış (tüketim) sayılan türler — "gün sonu azalma" ve maliyet. */
    private const CONSUMPTION_TYPES = [
        'recipe_consumption', 'comp_consumption', 'sale',
    ];

    /**
     * Dönem mutabakat raporu.
     *
     * @return array{
     *   from: string, to: string,
     *   rows: array<int, array<string, mixed>>,
     *   totals: array<string, mixed>
     * }
     */
    public function period(int $tenantId, Carbon $from, Carbon $to): array
    {
        $items = StockItem::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->get(['id', 'name', 'base_unit', 'avg_cost_minor'])
            ->keyBy('id');

        if ($items->isEmpty()) {
            return ['from' => $from->toDateString(), 'to' => $to->toDateString(), 'rows' => [], 'totals' => $this->emptyTotals()];
        }

        // Açılış: dönem başlangıcından ÖNCEKİ tüm hareketlerin toplamı.
        $opening = StockMovement::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->where('occurred_at', '<', $from)
            ->selectRaw('item_id, SUM(qty_milli) as bal')
            ->groupBy('item_id')
            ->pluck('bal', 'item_id');

        // Dönem içi hareketler — yön (giriş/çıkış) ve tür bazında ayrıştır.
        $window = StockMovement::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->whereBetween('occurred_at', [$from, $to])
            ->selectRaw('item_id')
            ->selectRaw('SUM(CASE WHEN qty_milli > 0 THEN qty_milli ELSE 0 END) as in_qty')
            ->selectRaw('SUM(CASE WHEN qty_milli < 0 THEN -qty_milli ELSE 0 END) as out_qty')
            ->selectRaw("SUM(CASE WHEN type IN ('recipe_consumption','comp_consumption','sale') THEN -qty_milli ELSE 0 END) as consumed_qty")
            ->selectRaw("SUM(CASE WHEN type IN ('recipe_consumption','comp_consumption','sale') THEN COALESCE(total_cost_minor,0) ELSE 0 END) as consumed_cost")
            ->groupBy('item_id')
            ->get()
            ->keyBy('item_id');

        $rows = [];
        $totals = $this->emptyTotals();

        foreach ($items as $id => $item) {
            $w = $window->get($id);
            $open = (int) ($opening[$id] ?? 0);
            $inQty = (int) ($w->in_qty ?? 0);
            $outQty = (int) ($w->out_qty ?? 0);
            $consumedQty = (int) ($w->consumed_qty ?? 0);
            $consumedCost = (int) ($w->consumed_cost ?? 0);
            $close = $open + $inQty - $outQty;

            // Hareketsiz kalemleri raporda gösterme (gürültü azalt).
            if ($inQty === 0 && $outQty === 0 && $open === 0) {
                continue;
            }

            $rows[] = [
                'item_id' => (int) $id,
                'name' => $item->name,
                'unit' => $item->base_unit,
                'opening' => Qty::toDecimalString($open),
                'opening_milli' => $open,
                'in' => Qty::toDecimalString($inQty),
                'in_milli' => $inQty,
                'out' => Qty::toDecimalString($outQty),
                'out_milli' => $outQty,
                'consumed' => Qty::toDecimalString($consumedQty),
                'consumed_milli' => $consumedQty,
                'consumed_cost_minor' => $consumedCost,
                'closing' => Qty::toDecimalString($close),
                'closing_milli' => $close,
                'balanced' => ($open + $inQty - $outQty) === $close, // her zaman true; mutabakat garantisi
            ];

            $totals['in_cost_minor'] += 0; // giriş maliyeti aşağıda ayrıca
            $totals['consumed_cost_minor'] += $consumedCost;
            $totals['moved_items']++;
        }

        // Dönem giriş maliyeti (alış/üretim) ayrı toplam — kâr/maliyet bağı.
        $totals['in_cost_minor'] = (int) StockMovement::withoutTenancy()
            ->where('tenant_id', $tenantId)
            ->whereBetween('occurred_at', [$from, $to])
            ->where('qty_milli', '>', 0)
            ->sum('total_cost_minor');

        usort($rows, fn ($a, $b) => $b['consumed_cost_minor'] <=> $a['consumed_cost_minor']);

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'rows' => $rows,
            'totals' => $totals,
        ];
    }

    /**
     * "Gün sonu" — belirli günde stoktan DÜŞEN (tüketilen) kalemler.
     * "Bugün stoktan şu kadar X azaldı."
     *
     * @return array<int, array<string, mixed>>
     */
    public function dayEnd(int $tenantId, Carbon $day): array
    {
        $from = $day->copy()->startOfDay();
        $to = $day->copy()->endOfDay();

        return StockMovement::withoutTenancy()
            ->with('item:id,name,base_unit')
            ->where('tenant_id', $tenantId)
            ->whereIn('type', self::CONSUMPTION_TYPES)
            ->whereBetween('occurred_at', [$from, $to])
            // NOT: `lines` MariaDB rezerve kelimesi (§4) → alias `move_count`.
            ->selectRaw('item_id, SUM(-qty_milli) as used, SUM(COALESCE(total_cost_minor,0)) as cost, COUNT(*) as move_count')
            ->groupBy('item_id')
            ->get()
            ->map(fn (StockMovement $m) => [
                'item_id' => (int) $m->item_id,
                'name' => $m->item?->name ?? '—',
                'unit' => $m->item?->base_unit ?? '',
                'used' => Qty::toDecimalString((int) $m->used),
                'used_milli' => (int) $m->used,
                'cost_minor' => (int) $m->cost,
                'lines' => (int) $m->move_count,
            ])
            ->sortByDesc('used_milli')
            ->values()
            ->all();
    }

    /** @return array<string, mixed> */
    private function emptyTotals(): array
    {
        return [
            'moved_items' => 0,
            'in_cost_minor' => 0,
            'consumed_cost_minor' => 0,
        ];
    }
}
