<?php

namespace App\Modules\Reports\Services;

use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;

/**
 * Satış raporları (salt-okur read-model).
 *
 * Tanımlar (tek yerde, tutarlı — 2026-07-23 düzeltmesi):
 * - "Ciro/Net Satış" = KAPANAN adisyonlar = status IN (paid,
 *   debt_transferred). Açık (henüz ödenmemiş/borca yazılmamış) adisyonlar
 *   Ciro'ya SAYILMAZ — bkz. openAmount(). İptal/iade Ciro DIŞIDIR.
 * - "Ciro = Tahsilat + Açık borç" denklemi: Tahsilat (gerçekten kasaya
 *   giren para, FinanceReportService::summary→collected_minor, `payments`
 *   kaynaklı) + Açık borç (cari bakiyeleri, ReceivablesReportService) bu
 *   raporun 'revenue_minor'ına eşit olmalıdır (debt_transferred'in tutarı
 *   ya zaten tahsil edilmişse Tahsilat'ta, edilmemiş kalan kısmıysa Açık
 *   borç'tadır).
 * - Açık masa tutarı Ciro DEĞİLDİR, AYRI gösterilir (bkz. openAmount()).
 * - Tutarlar kuruş-integer döner (ADR-007); biçimleme görüntü katmanında.
 * - Aralık kolonu orders.created_at → (tenant_id, created_at) indeksi.
 */
class SalesReportService
{
    /** Ciro'ya sayılan KAPANAN durumlar: ödendi ya da cariye borç yazıldı. */
    private const REVENUE_STATUSES = ['paid', 'debt_transferred'];

    /**
     * Açık masa/adisyon (henüz kapanmamış) sayılan durumlar dışındakiler —
     * yani "açık" kümesi bu listenin DIŞI: taslak/ödendi/iptal/iade/
     * borca-taşındı hariç HER ŞEY (onay bekleyen dahil, masa fiilen dolu).
     * Dashboard/occupancy ile AYNI tanım (tek yerde tutarlı).
     */
    private const OPEN_TABLE_EXCLUDED = ['draft', 'paid', 'cancelled', 'refunded', 'debt_transferred'];

    private function salesBase(ReportFilters $f): \Illuminate\Database\Query\Builder
    {
        return $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES);
    }

    /**
     * Açık masa tutarı (ANLIK): henüz kapanmamış adisyonların güncel
     * toplamı. Ciro DEĞİLDİR — para ne tahsil edildi ne cariye yazıldı,
     * yalnız "şu an masada duran tutar" bilgisidir. Dönem filtresi
     * UYGULANMAZ (occupancy/openOrders ile aynı desen — anlık durum).
     */
    public function openAmount(ReportFilters $f): array
    {
        $query = DB::table('orders')
            ->where('orders.tenant_id', $f->tenantId)
            ->whereNotIn('orders.status', self::OPEN_TABLE_EXCLUDED);

        if ($f->branchId !== null) {
            $query->where('orders.branch_id', $f->branchId);
        }

        $row = $query->selectRaw('COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t')->first();

        return ['orders' => (int) $row->c, 'total_minor' => (int) $row->t];
    }

    /** Dönem özeti + önceki dönem karşılaştırması. */
    public function summary(ReportFilters $f): array
    {
        $current = $this->periodTotals($this->salesBase($f));
        $previous = $this->periodTotals(
            $f->applyPrevious(DB::table('orders'), 'orders')
                ->whereIn('orders.status', self::REVENUE_STATUSES)
        );

        $cancelled = $f->apply(DB::table('orders'), 'orders')
            ->where('orders.status', 'cancelled')
            ->selectRaw('COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t')
            ->first();

        return [
            'current' => $current,
            'previous' => $previous,
            'cancelled' => ['orders' => (int) $cancelled->c, 'total_minor' => (int) $cancelled->t],
        ];
    }

    private function periodTotals(\Illuminate\Database\Query\Builder $query): array
    {
        $row = $query->selectRaw(
            'COUNT(*) AS orders_count,
             COALESCE(SUM(orders.total_minor), 0) AS revenue_minor,
             COALESCE(SUM(orders.guest_count), 0) AS guests,
             COUNT(orders.guest_count) AS orders_with_guests,
             COALESCE(SUM(CASE WHEN orders.guest_count IS NOT NULL THEN orders.total_minor END), 0) AS revenue_with_guests_minor'
        )->first();

        $ordersCount = (int) $row->orders_count;
        $guests = (int) $row->guests;

        return [
            'orders' => $ordersCount,
            'revenue_minor' => (int) $row->revenue_minor,
            'avg_basket_minor' => $ordersCount > 0 ? intdiv((int) $row->revenue_minor, $ordersCount) : 0,
            // Kişi başı harcama YALNIZ misafir sayısı girilmiş adisyonlardan (uydurma payda yok).
            'guests' => $guests,
            'per_guest_minor' => $guests > 0 ? intdiv((int) $row->revenue_with_guests_minor, $guests) : null,
        ];
    }

    /** Günlük satış serisi (boş günler 0 ile doldurulur — eksen sürekliliği). */
    public function daily(ReportFilters $f): array
    {
        $day = $f->dayExpr('orders.created_at');

        $rows = $this->salesBase($f)
            ->selectRaw("{$day} AS d, COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t")
            ->groupBy('d')->orderBy('d')
            ->get()->keyBy('d');

        $days = [];
        $cursor = \Carbon\CarbonImmutable::parse($f->from, $f->timezone);
        $end = \Carbon\CarbonImmutable::parse($f->to, $f->timezone);

        while ($cursor->lte($end)) {
            $key = $cursor->toDateString();
            $row = $rows->get($key);
            $count = (int) ($row->c ?? 0);
            $total = (int) ($row->t ?? 0);
            $days[] = [
                'date' => $key,
                'orders' => $count,
                'revenue_minor' => $total,
                'avg_basket_minor' => $count > 0 ? intdiv($total, $count) : 0,
            ];
            $cursor = $cursor->addDay();
        }

        return ['days' => $days];
    }

    /** Saatlik dağılım (yoğun saatler): 0-23, şube saatiyle. */
    public function hourly(ReportFilters $f): array
    {
        $hour = $f->hourExpr('orders.created_at');

        $rows = $this->salesBase($f)
            ->selectRaw("{$hour} AS h, COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t")
            ->groupBy('h')->orderBy('h')
            ->get()->keyBy('h');

        $hours = [];
        for ($h = 0; $h < 24; $h++) {
            $row = $rows->get($h);
            $hours[] = [
                'hour' => $h,
                'orders' => (int) ($row->c ?? 0),
                'revenue_minor' => (int) ($row->t ?? 0),
            ];
        }

        return ['hours' => $hours];
    }

    /**
     * Kategori satışları. Kalem SNAPSHOT esastır (line_total_minor); kategori
     * bugünkü ürün kaydından okunur — ürünü silinmiş kalemler "Silinmiş ürün"
     * altında DÜRÜSTÇE ayrı gösterilir, kaybolmaz.
     */
    public function categories(ReportFilters $f): array
    {
        $rows = $this->itemsBase($f)
            ->leftJoin('products', 'products.id', '=', 'order_items.product_id')
            ->leftJoin('categories', 'categories.id', '=', 'products.category_id')
            ->selectRaw(
                "COALESCE(categories.name, CASE WHEN order_items.product_id IS NULL THEN 'Silinmiş ürün' ELSE 'Kategorisiz' END) AS name,
                 COALESCE(SUM(order_items.qty), 0) AS qty,
                 COALESCE(SUM(order_items.line_total_minor), 0) AS revenue_minor,
                 COUNT(DISTINCT order_items.order_id) AS orders_count"
            )
            // 'name' TAM İFADEYLE grupla: `GROUP BY name` alias ile order_items.name /
            // categories.name arasında BELİRSİZ (SQLite hata verir). İfade aynı → davranış değişmez.
            ->groupBy(DB::raw("COALESCE(categories.name, CASE WHEN order_items.product_id IS NULL THEN 'Silinmiş ürün' ELSE 'Kategorisiz' END)"))
            ->orderByDesc('revenue_minor')
            ->get();

        return ['rows' => $this->castRows($rows)];
    }

    /**
     * Ürün satışları (kalem adı = satış anı snapshot'ı). Adet azalana göre
     * sıralanır — 'rows' böylece doğrudan "en çok satılan" listesidir.
     * 'least_by_qty': en az satılan (ama en az 1 satılmış) ürünler — hiç
     * satılmayan menü kalemleri BURADA YOKTUR (bu, katalogla kıyaslama
     * ister; dürüstçe kapsam dışı bırakılır, uydurma 0 satır eklenmez).
     */
    public function products(ReportFilters $f): array
    {
        $rows = $this->itemsBase($f)
            ->selectRaw(
                'order_items.name AS name,
                 COALESCE(SUM(order_items.qty), 0) AS qty,
                 COALESCE(SUM(order_items.line_total_minor), 0) AS revenue_minor,
                 COUNT(DISTINCT order_items.order_id) AS orders_count'
            )
            ->groupBy('order_items.name')
            ->orderByDesc('qty')
            ->limit(500)
            ->get();

        $cast = $this->castRows($rows);

        return [
            'rows' => $cast,
            'top_by_qty' => array_slice($cast, 0, 15),
            'least_by_qty' => collect($cast)->sortBy('qty')->take(15)->values()->all(),
        ];
    }

    /** Varyant satışları (yalnız varyantlı kalemler). */
    public function variants(ReportFilters $f): array
    {
        $rows = $this->itemsBase($f)
            ->whereNotNull('order_items.variant_name')
            ->selectRaw(
                'order_items.name AS name,
                 order_items.variant_name AS variant,
                 COALESCE(SUM(order_items.qty), 0) AS qty,
                 COALESCE(SUM(order_items.line_total_minor), 0) AS revenue_minor'
            )
            ->groupBy('order_items.name', 'order_items.variant_name')
            ->orderByDesc('revenue_minor')
            ->limit(200)
            ->get();

        return [
            'rows' => $rows->map(fn ($r) => [
                'name' => (string) $r->name,
                'variant' => (string) $r->variant,
                'qty' => (int) $r->qty,
                'revenue_minor' => (int) $r->revenue_minor,
            ])->all(),
        ];
    }

    /** Masa satışları + devir hızı + ortalama oturum süresi. */
    public function tables(ReportFilters $f): array
    {
        $minutes = $f->minutesExpr('orders.placed_at', 'orders.closed_at');

        $rows = $this->salesBase($f)
            ->leftJoin('tables', 'tables.id', '=', 'orders.table_id')
            ->whereNotNull('orders.table_id')
            ->selectRaw(
                "COALESCE(tables.name, 'Silinmiş masa') AS name,
                 COUNT(*) AS orders_count,
                 COALESCE(SUM(orders.total_minor), 0) AS revenue_minor,
                 COUNT(orders.closed_at) AS turns,
                 AVG(CASE WHEN orders.closed_at IS NOT NULL AND orders.placed_at IS NOT NULL THEN {$minutes} END) AS avg_minutes"
            )
            ->groupBy('name')
            ->orderByDesc('revenue_minor')
            ->get();

        return [
            'rows' => $rows->map(fn ($r) => [
                'name' => (string) $r->name,
                'orders' => (int) $r->orders_count,
                'revenue_minor' => (int) $r->revenue_minor,
                'turns' => (int) $r->turns, // kapanan adisyon = devir
                'avg_minutes' => $r->avg_minutes !== null ? round((float) $r->avg_minutes, 1) : null,
            ])->all(),
        ];
    }

    /** Kanal kırılımı (masa/paket/gel-al/kiosk/QR). */
    public function channels(ReportFilters $f): array
    {
        $rows = $this->salesBase($f)
            ->selectRaw('orders.channel AS channel, COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t')
            ->groupBy('orders.channel')
            ->orderByDesc('t')
            ->get();

        $total = (int) $rows->sum('t');

        return [
            'total_minor' => $total,
            'rows' => $rows->map(fn ($r) => [
                'channel' => (string) $r->channel,
                'label' => OrderChannel::tryFrom((string) $r->channel)?->label() ?? (string) $r->channel,
                'orders' => (int) $r->c,
                'revenue_minor' => (int) $r->t,
                'share' => $total > 0 ? round(((int) $r->t) * 100 / $total, 1) : 0.0,
            ])->all(),
        ];
    }

    /* ---------------------------------------------------------------- */

    /**
     * İptal/ikram DIŞI satılan kalemler. Dönem ataması ADİSYON tarihiyle
     * yapılır (orders.created_at → mevcut (tenant_id, created_at) indeksi);
     * ikram kalemleri satış adedini şişirmesin diye dışarıda tutulur
     * (değerleri finans/operasyon raporunda görünür).
     */
    private function itemsBase(ReportFilters $f): \Illuminate\Database\Query\Builder
    {
        return $this->salesBase($f)
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.status', '!=', 'cancelled')
            ->where('order_items.is_comp', false);
    }

    private function castRows(\Illuminate\Support\Collection $rows): array
    {
        return $rows->map(fn ($r) => [
            'name' => (string) $r->name,
            'qty' => (int) $r->qty,
            'revenue_minor' => (int) $r->revenue_minor,
            'orders' => (int) $r->orders_count,
        ])->all();
    }
}
