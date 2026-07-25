<?php

namespace App\Modules\Reports\Services;

use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\OrderStatus;
use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;

/**
 * Operasyon raporları: gün sonu özeti, geciken siparişler, istasyon hazırlama süreleri,
 * servis talebi yanıt süresi, iptal/ikram nedenleri, QR/kiosk kullanımı.
 * Süreler order_events / service_requests zaman damgalarından türetilir —
 * kayıt yoksa süre UYDURULMAZ, satır "veri yok" olarak işaretlenir.
 */
class OpsReportService
{
    private const EXCLUDED = ['draft', 'pending_approval', 'cancelled'];

    public function __construct(
        private readonly SalesReportService $sales,
        private readonly FinanceReportService $finance,
        private readonly ReceivablesReportService $receivables,
        private readonly ProductReportService $products,
    ) {
    }

    /**
     * Gün sonu raporu (operasyonel özet — Z BENZERİ ama Z DEĞİL). Seçilen
     * tarih aralığı için ciro, açılan/kapanan adisyon, ortalama sepet,
     * kişi sayısı ve iptal/ikram/indirim/iade toplamlarını TEK ekranda
     * toplar. Ödeme yöntemi kırılımı (finance-payment-methods) ve yoğun
     * saatler (sales-hourly) ZATEN AYRI raporlar — burada TEKRARLANMAZ;
     * ekran bu iki raporu da aynı filtreyle ayrıca çeker (tek doğruluk
     * kaynağı, kopya SQL yok).
     *
     * NOT: Kasa Z raporu (kasa açma/kapama, sayım) Payments modülündedir
     * ve BUNUN YERİNE GEÇMEZ; bu rapor kasadan bağımsız, o günün TÜM
     * operasyonuna (mutfak/servis dahil) bakar — tamamlayıcıdır.
     *
     * NOT (2026-07-23): dört para büyüklüğü BURADA AYRI görünür, birbirine
     * KARIŞTIRILMAZ — Ciro (revenue_minor, yalnız KAPANAN adisyonlar),
     * Tahsilat (collected_minor, `payments`'tan gerçek tahsilat),
     * Açık masa (open_table_minor, ANLIK, henüz kapanmamış adisyonlar) ve
     * Açık borç (open_receivables_total_minor, cari bakiyeleri). Ciro ≈
     * Tahsilat + Açık borç (bkz. SalesReportService docblock).
     */
    public function endOfDay(ReportFilters $f): array
    {
        $sales = $this->sales->summary($f)['current'];
        $finance = $this->finance->summary($f);
        // Açık masa tutarı (ANLIK) — Ciro DEĞİLDİR, ayrı gösterilir.
        $openTable = $this->sales->openAmount($f);

        // Açılan adisyon: bu aralıkta fiilen sipariş verilmiş (placed_at).
        $opened = (int) $f->apply(DB::table('orders'), 'orders', 'placed_at')
            ->whereNotNull('orders.placed_at')
            ->count();

        // Kapanan adisyon: bu aralıkta ödenip kapatılmış (closed_at).
        $closed = (int) $f->apply(DB::table('orders'), 'orders', 'closed_at')
            ->whereNotNull('orders.closed_at')
            ->count();

        // Açık cariler (GÜNCEL toplam): Receivables modülü şeması yoksa
        // 'available'=false — alanlar null kalır, uydurma sayı YOK.
        $open = $this->receivables->openAccounts($f);

        // İkram (comp): gelir getirmeyen ama stok/maliyet tüketen kalemler
        // (adet + tutar + GÜNCEL maliyet). Kârlılık ekranıyla aynı kaynak.
        $comp = $this->products->compSummary($f);

        // Ciro vs Tahsilat netliği (#9): "Ciro (borç dahil)" içine borca
        // taşınan (debt_transferred) tutar da girer ama HENÜZ TAHSİL
        // EDİLMEDİ — kalan bakiyesi ayrıca gösterilir ("borca taşınan X₺
        // dahil, henüz tahsil edilmedi").
        $debt = $f->apply(DB::table('orders'), 'orders')
            ->where('orders.status', 'debt_transferred')
            ->selectRaw(
                'COUNT(*) AS c,
                 COALESCE(SUM(orders.total_minor), 0) AS total,
                 COALESCE(SUM(orders.total_minor - orders.paid_minor), 0) AS balance'
            )->first();

        return [
            'from' => $f->from,
            'to' => $f->to,
            'orders' => $sales['orders'],
            'revenue_minor' => $sales['revenue_minor'],
            'avg_basket_minor' => $sales['avg_basket_minor'],
            'guests' => $sales['guests'],
            'per_guest_minor' => $sales['per_guest_minor'],
            'orders_opened' => $opened,
            'orders_closed' => $closed,
            'order_discount_minor' => $finance['order_discount_minor'],
            'item_discount_minor' => $finance['item_discount_minor'],
            'discount_total_minor' => $finance['order_discount_minor'] + $finance['item_discount_minor'],
            'comp_minor' => $finance['comp_minor'],
            // İkram maliyeti (stok tüketimi) — gün sonu/kârlılık için.
            'comp_count' => $comp['qty'],
            'comp_items' => $comp['items'],
            'comp_cost_minor' => $comp['cost_minor'],
            'comp_cost_known_items' => $comp['cost_known_items'],
            'comp_missing_cost_items' => $comp['missing_cost_items'],
            // Ciro içindeki borca-taşınan pay (henüz tahsil edilmemiş kısım).
            'debt_transferred_count' => (int) $debt->c,
            'debt_transferred_minor' => (int) $debt->total,
            'debt_transferred_balance_minor' => (int) $debt->balance,
            'cancelled_orders' => $finance['cancelled_orders'],
            'cancelled_minor' => $finance['cancelled_minor'],
            'refunded_minor' => $finance['refunded_minor'],
            'refund_payments_count' => $finance['refund_payments_count'],
            'refund_payments_minor' => $finance['refund_payments_minor'],
            'collected_minor' => $finance['collected_minor'],
            'collected_count' => $finance['collected_count'],
            'tips_minor' => $finance['tips_minor'],
            'open_receivables_available' => $open['available'],
            'open_receivables_count' => $open['count'],
            'open_receivables_total_minor' => $open['total_minor'],
            'open_table_orders' => $openTable['orders'],
            'open_table_minor' => $openTable['total_minor'],
        ];
    }

    /** ŞU AN geciken açık siparişler (mutfak aşamasında eşikten eski). */
    public function delayed(ReportFilters $f): array
    {
        $thresholdMinutes = (int) config('reports.delayed_threshold_minutes', 20);
        $cutoff = now()->subMinutes($thresholdMinutes);

        $kitchenStatuses = array_map(
            fn (OrderStatus $s) => $s->value,
            array_filter(OrderStatus::cases(), fn (OrderStatus $s) => $s->isKitchenPhase() && $s !== OrderStatus::Served),
        );

        $query = DB::table('orders')
            ->where('orders.tenant_id', $f->tenantId)
            ->whereIn('orders.status', array_values($kitchenStatuses))
            ->where('orders.created_at', '<', $cutoff);

        if ($f->branchId !== null) {
            $query->where('orders.branch_id', $f->branchId);
        }

        $rows = $query
            ->leftJoin('tables', 'tables.id', '=', 'orders.table_id')
            ->orderBy('orders.created_at')
            ->limit(100)
            ->get([
                'orders.id', 'orders.status', 'orders.channel', 'orders.created_at',
                'orders.total_minor', 'tables.name AS table_name',
            ]);

        return [
            'threshold_minutes' => $thresholdMinutes,
            'rows' => $rows->map(fn ($r) => [
                'id' => (int) $r->id,
                'status' => (string) $r->status,
                'status_label' => OrderStatus::tryFrom((string) $r->status)?->label() ?? (string) $r->status,
                'channel' => (string) $r->channel,
                'table' => $r->table_name !== null ? (string) $r->table_name : null,
                'created_at' => $r->created_at,
                'age_minutes' => (int) floor(now()->diffInSeconds(\Carbon\Carbon::parse($r->created_at)) / 60),
                'total_minor' => (int) $r->total_minor,
            ])->all(),
        ];
    }

    /** İstasyon başına ortalama hazırlama süresi (kalem eklendi → hazır olayı). */
    public function stationPrep(ReportFilters $f): array
    {
        $minutes = $f->minutesExpr('order_items.created_at', 'ready_events.created_at');

        $rows = $f->apply(DB::table('orders'), 'orders')
            ->whereNotIn('orders.status', self::EXCLUDED)
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->join('order_events AS ready_events', function ($join): void {
                $join->on('ready_events.order_item_id', '=', 'order_items.id')
                    ->where('ready_events.to_status', '=', 'ready');
            })
            ->selectRaw(
                "COALESCE(order_items.station, 'belirsiz') AS station,
                 COUNT(DISTINCT order_items.id) AS items,
                 AVG({$minutes}) AS avg_minutes,
                 MAX({$minutes}) AS max_minutes"
            )
            ->groupBy('station')
            ->orderByDesc('items')
            ->get();

        return [
            'rows' => $rows->map(fn ($r) => [
                'station' => (string) $r->station,
                'items' => (int) $r->items,
                'avg_minutes' => $r->avg_minutes !== null ? round((float) $r->avg_minutes, 1) : null,
                'max_minutes' => $r->max_minutes !== null ? round((float) $r->max_minutes, 1) : null,
            ])->all(),
        ];
    }

    /** Garson çağrısı / hesap / su taleplerine yanıt süresi. */
    public function serviceRequests(ReportFilters $f): array
    {
        $minutes = $f->minutesExpr('service_requests.created_at', 'service_requests.handled_at');

        $rows = $f->apply(DB::table('service_requests'), 'service_requests')
            ->selectRaw(
                "service_requests.kind AS kind,
                 COUNT(*) AS total,
                 SUM(CASE WHEN service_requests.status = 'open' THEN 1 ELSE 0 END) AS open_count,
                 AVG(CASE WHEN service_requests.handled_at IS NOT NULL THEN {$minutes} END) AS avg_minutes"
            )
            ->groupBy('service_requests.kind')
            ->orderByDesc('total')
            ->get();

        $labels = ['waiter' => 'Garson çağrısı', 'bill' => 'Hesap istendi', 'water' => 'Su istendi'];

        return [
            'rows' => $rows->map(fn ($r) => [
                'kind' => (string) $r->kind,
                'label' => $labels[(string) $r->kind] ?? (string) $r->kind,
                'total' => (int) $r->total,
                'open' => (int) $r->open_count,
                'avg_response_minutes' => $r->avg_minutes !== null ? round((float) $r->avg_minutes, 1) : null,
            ])->all(),
        ];
    }

    /** İptal ve ikram nedenleri (adisyon + kalem düzeyi). */
    public function cancellations(ReportFilters $f): array
    {
        $orderCancels = $f->apply(DB::table('orders'), 'orders')
            ->where('orders.status', 'cancelled')
            ->selectRaw(
                "COALESCE(orders.cancel_reason, '(neden girilmemiş)') AS reason,
                 COUNT(*) AS c,
                 COALESCE(SUM(orders.total_minor), 0) AS t"
            )
            ->groupBy('reason')->orderByDesc('c')->get();

        $itemCancels = $f->apply(DB::table('orders'), 'orders')
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.status', 'cancelled')
            ->selectRaw(
                "COALESCE(order_items.cancel_reason, '(neden girilmemiş)') AS reason,
                 COUNT(*) AS c,
                 COALESCE(SUM(order_items.qty * (order_items.unit_price_minor + order_items.options_price_minor)), 0) AS t"
            )
            ->groupBy('reason')->orderByDesc('c')->get();

        $comps = $f->apply(DB::table('orders'), 'orders')
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.is_comp', true)
            ->where('order_items.status', '!=', 'cancelled')
            ->selectRaw(
                "COALESCE(order_items.comp_reason, '(neden girilmemiş)') AS reason,
                 COUNT(*) AS c,
                 COALESCE(SUM(order_items.qty * (order_items.unit_price_minor + order_items.options_price_minor)), 0) AS t"
            )
            ->groupBy('reason')->orderByDesc('c')->get();

        $cast = fn ($rows) => $rows->map(fn ($r) => [
            'reason' => (string) $r->reason,
            'count' => (int) $r->c,
            'value_minor' => (int) $r->t,
        ])->all();

        return [
            'order_cancels' => $cast($orderCancels),
            'item_cancels' => $cast($itemCancels),
            'comps' => $cast($comps),
        ];
    }

    /** QR/kiosk kullanımı: kanal payları + günlük QR okutma sayısı. */
    public function channelUsage(ReportFilters $f): array
    {
        $orders = $f->apply(DB::table('orders'), 'orders')
            ->whereNotIn('orders.status', ['draft'])
            ->selectRaw('orders.channel AS channel, COUNT(*) AS c')
            ->groupBy('orders.channel')
            ->get();

        $totalOrders = (int) $orders->sum('c');

        // qr_scans şube kolonu taşımaz; kiracı + tarih indeksiyle sayılır.
        $day = $f->dayExpr('qr_scans.created_at');
        $scans = DB::table('qr_scans')
            ->where('qr_scans.tenant_id', $f->tenantId)
            ->where('qr_scans.created_at', '>=', $f->fromUtc)
            ->where('qr_scans.created_at', '<', $f->toUtc)
            ->selectRaw("{$day} AS d, COUNT(*) AS c, SUM(CASE WHEN qr_scans.result = 'ok' THEN 1 ELSE 0 END) AS ok_count")
            ->groupBy('d')->orderBy('d')
            ->get();

        return [
            'orders_total' => $totalOrders,
            'channels' => $orders->map(fn ($r) => [
                'channel' => (string) $r->channel,
                'label' => OrderChannel::tryFrom((string) $r->channel)?->label() ?? (string) $r->channel,
                'orders' => (int) $r->c,
                'share' => $totalOrders > 0 ? round(((int) $r->c) * 100 / $totalOrders, 1) : 0.0,
            ])->all(),
            'scans' => $scans->map(fn ($r) => [
                'date' => (string) $r->d,
                'total' => (int) $r->c,
                'ok' => (int) $r->ok_count,
            ])->all(),
        ];
    }
}
