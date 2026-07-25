<?php

namespace App\Modules\Reports\Services;

use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;

/**
 * Ürün kârlılık raporu.
 *
 * DÜRÜSTLÜK NOTU: sipariş kalemi maliyeti SNAPSHOT'lamaz; maliyet, katalog
 * kartındaki GÜNCEL `products.cost_minor` değeridir. Maliyeti girilmemiş
 * ürünlerde kâr HESAPLANMAZ (null döner, 0 uydurulmaz) ve satır
 * `has_cost=false` ile işaretlenir.
 */
class ProductReportService
{
    private const EXCLUDED = ['draft', 'pending_approval', 'cancelled'];

    public function profitability(ReportFilters $f): array
    {
        $rows = $f->apply(DB::table('orders'), 'orders')
            ->whereNotIn('orders.status', self::EXCLUDED)
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.status', '!=', 'cancelled')
            ->where('order_items.is_comp', false)
            ->leftJoin('products', 'products.id', '=', 'order_items.product_id')
            ->selectRaw(
                'COALESCE(MAX(products.name), order_items.name) AS name,
                 order_items.product_id AS product_id,
                 MAX(products.cost_minor) AS cost_minor,
                 COALESCE(SUM(order_items.qty), 0) AS qty,
                 COALESCE(SUM(order_items.line_total_minor), 0) AS revenue_minor,
                 COALESCE(SUM(order_items.vat_minor), 0) AS vat_minor'
            )
            ->groupBy('order_items.product_id', 'order_items.name')
            ->orderByDesc('revenue_minor')
            ->limit(300)
            ->get();

        $out = [];
        $missingCost = 0;

        foreach ($rows as $r) {
            $qty = (int) $r->qty;
            $revenue = (int) $r->revenue_minor;
            $net = $revenue - (int) $r->vat_minor; // kâr KDV hariç tutardan
            $hasCost = $r->product_id !== null && $r->cost_minor !== null;

            $cost = $hasCost ? (int) $r->cost_minor * $qty : null;
            $profit = $hasCost ? $net - $cost : null;

            if (! $hasCost) {
                $missingCost++;
            }

            $out[] = [
                'name' => (string) $r->name,
                'qty' => $qty,
                'revenue_minor' => $revenue,
                'net_minor' => $net,
                'unit_cost_minor' => $hasCost ? (int) $r->cost_minor : null,
                'cost_minor' => $cost,
                'profit_minor' => $profit,
                'margin' => $hasCost && $net > 0 ? round($profit * 100 / $net, 1) : null,
                'has_cost' => $hasCost,
            ];
        }

        // "Çok satan ama düşük kârlı" işareti: adet medyanın üstünde ve
        // marj, maliyeti bilinen ürünlerin medyan marjının altında.
        $withCost = array_values(array_filter($out, fn ($r) => $r['has_cost'] && $r['margin'] !== null));
        $medianMargin = $this->median(array_column($withCost, 'margin'));
        $medianQty = $this->median(array_column($out, 'qty'));

        foreach ($out as &$row) {
            $row['high_volume_low_margin'] = $row['has_cost']
                && $medianMargin !== null && $medianQty !== null
                && $row['qty'] >= $medianQty
                && $row['margin'] !== null && $row['margin'] < $medianMargin;
        }

        return [
            'rows' => $out,
            'missing_cost_count' => $missingCost,
            'median_margin' => $medianMargin,
        ];
    }

    private function median(array $values): ?float
    {
        $values = array_values(array_filter($values, fn ($v) => $v !== null));
        if ($values === []) {
            return null;
        }
        sort($values);
        $n = count($values);
        $mid = intdiv($n, 2);

        return $n % 2 === 1 ? (float) $values[$mid] : ($values[$mid - 1] + $values[$mid]) / 2;
    }
}
