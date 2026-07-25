<?php

namespace App\Modules\Reports\Services;

use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;

/**
 * Personel raporu — DENGELİ metrik seti (prompt §7): yalnız satış tutarı
 * değil; sipariş adedi, servis süresi, indirim/ikram/iptal oranları ve
 * servis talebi karşılama birlikte gösterilir. Tek metriğe göre sıralayıp
 * "en iyi garson" ilan etmek yanıltıcıdır; ekran da bunu vurgular.
 */
class StaffReportService
{
    private const EXCLUDED = ['draft', 'pending_approval', 'cancelled'];

    public function performance(ReportFilters $f): array
    {
        // Adisyon açan bazında satış + süre.
        $minutes = $f->minutesExpr('orders.placed_at', 'orders.closed_at');

        $orders = $f->apply(DB::table('orders'), 'orders')
            ->whereNotNull('orders.opened_by_id')
            ->selectRaw(
                "orders.opened_by_id AS user_id,
                 SUM(CASE WHEN orders.status NOT IN ('draft','pending_approval','cancelled') THEN 1 ELSE 0 END) AS orders_count,
                 COALESCE(SUM(CASE WHEN orders.status NOT IN ('draft','pending_approval','cancelled') THEN orders.total_minor ELSE 0 END), 0) AS sales_minor,
                 COALESCE(SUM(CASE WHEN orders.status NOT IN ('draft','pending_approval','cancelled') THEN orders.discount_minor ELSE 0 END), 0) AS discount_minor,
                 SUM(CASE WHEN orders.status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count,
                 AVG(CASE WHEN orders.closed_at IS NOT NULL AND orders.placed_at IS NOT NULL THEN {$minutes} END) AS avg_service_minutes"
            )
            ->groupBy('orders.opened_by_id')
            ->get()
            ->keyBy('user_id');

        // Kalem bazlı: eklenen kalem, ikram, satır indirimi.
        $items = $f->apply(DB::table('orders'), 'orders')
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->whereNotNull('order_items.added_by_id')
            ->selectRaw(
                "order_items.added_by_id AS user_id,
                 COUNT(*) AS items_count,
                 SUM(CASE WHEN order_items.is_comp = 1 THEN 1 ELSE 0 END) AS comp_count,
                 COALESCE(SUM(CASE WHEN order_items.is_comp = 1 THEN order_items.qty * (order_items.unit_price_minor + order_items.options_price_minor) ELSE 0 END), 0) AS comp_minor,
                 COALESCE(SUM(order_items.discount_minor), 0) AS item_discount_minor"
            )
            ->groupBy('order_items.added_by_id')
            ->get()
            ->keyBy('user_id');

        // Servis taleplerini karşılama.
        $handled = $f->apply(DB::table('service_requests'), 'service_requests')
            ->whereNotNull('service_requests.handled_by_id')
            ->selectRaw('service_requests.handled_by_id AS user_id, COUNT(*) AS c')
            ->groupBy('service_requests.handled_by_id')
            ->get()
            ->keyBy('user_id');

        $userIds = $orders->keys()
            ->merge($items->keys())
            ->merge($handled->keys())
            ->unique()->values();

        if ($userIds->isEmpty()) {
            return ['rows' => []];
        }

        $users = DB::table('users')
            ->where('tenant_id', $f->tenantId)
            ->whereIn('id', $userIds)
            ->pluck('name', 'id');

        $rows = [];
        foreach ($userIds as $id) {
            $o = $orders->get($id);
            $i = $items->get($id);
            $h = $handled->get($id);

            $ordersCount = (int) ($o->orders_count ?? 0);
            $salesMinor = (int) ($o->sales_minor ?? 0);
            $cancelled = (int) ($o->cancelled_count ?? 0);
            $totalOpened = $ordersCount + $cancelled;

            $rows[] = [
                'user_id' => (int) $id,
                'name' => (string) ($users[$id] ?? 'Ayrılmış personel'),
                'orders' => $ordersCount,
                'items' => (int) ($i->items_count ?? 0),
                'sales_minor' => $salesMinor,
                'avg_basket_minor' => $ordersCount > 0 ? intdiv($salesMinor, $ordersCount) : 0,
                'avg_service_minutes' => isset($o->avg_service_minutes) && $o->avg_service_minutes !== null
                    ? round((float) $o->avg_service_minutes, 1)
                    : null,
                'discount_minor' => (int) ($o->discount_minor ?? 0) + (int) ($i->item_discount_minor ?? 0),
                'comp_count' => (int) ($i->comp_count ?? 0),
                'comp_minor' => (int) ($i->comp_minor ?? 0),
                'cancelled' => $cancelled,
                'cancel_rate' => $totalOpened > 0 ? round($cancelled * 100 / $totalOpened, 1) : 0.0,
                'requests_handled' => (int) ($h->c ?? 0),
            ];
        }

        usort($rows, fn ($a, $b) => $b['orders'] <=> $a['orders']);

        return ['rows' => $rows];
    }
}
