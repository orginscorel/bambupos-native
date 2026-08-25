<?php

declare(strict_types=1);

namespace App\Modules\Boss\Services;

use App\Modules\Commission\Services\CommissionService;
use App\Modules\Inventory\Support\InventoryFeature;
use App\Modules\Inventory\Support\Qty;
use App\Modules\Orders\Enums\OrderChannel;
use App\Modules\Orders\Enums\ServiceType;
use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Reports\Services\SalesReportService;
use App\Modules\Reports\Support\ReportFilters;
use App\Modules\Settings\Support\Features;
use App\Modules\Shifts\Models\Shift;
use App\Modules\Shifts\Models\TimeEntry;
use App\Modules\Tenancy\BranchContext;
use App\Modules\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * YÖNETİM KOKPİTİ derleme servisi (BOSS).
 *
 * Patron/yönetici için TEK ekranlık özet: verileri kopyalamadan MEVCUT
 * modüllerden (Satış/Ödeme/Stok/Performans/Prim/Teslimat) okur ve tek bir
 * DTO'da toplar. Kendi tablosu/yazması YOKTUR — salt-okur read-model.
 *
 * ŞUBE GÜVENLİĞİ: tüm sorgular ReportFilters (kiracı + geçerli şube +
 * tarih) ya da elle tenant_id/branch_id süzgeciyle koşar. İstekten gelen
 * branch_id'ye ASLA güvenilmez; şube kimliği çağıran (BranchContext)
 * tarafından çözülür. Çapraz-şube ciro/personel/borç ASLA sızmaz.
 *
 * DAYANIKLILIK: veri yoksa alanlar 0/null döner; boş durumu ekran anlatır
 * (uydurma sayı yok, çökme yok).
 */
final class BossService
{
    /** Ciro'ya sayılan KAPANAN adisyon durumları (SalesReportService ile aynı). */
    private const REVENUE_STATUSES = ['paid', 'debt_transferred'];

    /** Açık adisyon/masa DIŞI bırakılan durumlar (dashboard ile aynı tanım). */
    private const OPEN_EXCLUDED = ['draft', 'paid', 'cancelled', 'refunded', 'debt_transferred'];

    public function __construct(
        private readonly SalesReportService $sales,
        private readonly CommissionService $commission,
        private readonly TenantContext $tenants,
        private readonly BranchContext $branches,
    ) {
    }

    /**
     * Kokpit özeti. $from/$to şube saat diliminde 'Y-m-d'; $branchId geçerli
     * şube (null = kiracı geneli — yalnız yetkili sahip/müdür için çağrılır).
     *
     * @return array<string, mixed>
     */
    public function overview(string $from, string $to, ?int $branchId): array
    {
        $tenantId = (int) $this->tenants->tenantId();
        $timezone = (string) ($this->branches->currentBranch()?->timezone ?? config('app.timezone'));

        $filters = ReportFilters::fromArray([
            'tenant_id' => $tenantId,
            'branch_id' => $branchId,
            'timezone' => $timezone,
            'from' => $from,
            'to' => $to,
        ]);

        return [
            'range' => [
                'from' => $filters->from,
                'to' => $filters->to,
                'branch_id' => $branchId,
                'timezone' => $timezone,
            ],
            'sales' => $this->salesSection($filters),
            'by_day' => $byDay = $this->byDay($filters),
            'by_hour' => $this->byHour($filters),
            'by_weekday' => $this->byWeekday($byDay),
            'payment_mix' => $this->paymentMix($filters),
            'service_types' => $this->serviceTypes($filters),
            'channel_mix' => $this->sales->channels($filters),
            'top_products' => $this->topProducts($filters),
            'top_categories' => $this->topCategories($filters),
            'top_tables' => $this->topTables($filters),
            'discounts' => $this->discountsSection($filters),
            'open' => $this->openSection($filters, $tenantId, $branchId),
            'staff' => $this->staffSection($filters, $branchId),
            'on_shift' => $this->onShiftSection($branchId),
            'upcoming_today' => $this->upcomingTodaySection($branchId, $timezone),
            'inventory' => $this->inventorySection($tenantId),
            'delivery' => $this->deliverySection($filters, $tenantId, $branchId),
            'operations' => $this->operationsSection($filters),
        ];
    }

    /* ---------------- Operasyon metrikleri (executive) ---------------- */

    /**
     * Dönemin operasyonel göstergeleri — tümü MEVCUT orders alanlarından türetilir:
     *  - misafir sayısı + kişi başı ciro (guest_count),
     *  - ortalama servis süresi dk (placed_at → closed_at),
     *  - masa devir hızı (masalı sipariş / farklı masa),
     *  - QR self-servis payı (channel=qr),
     *  - iptal oranı,
     *  - en yoğun saat + en iyi gün.
     * Veri yoksa alanlar null/0 (uydurma yok). ŞUBE-GÜVENLİ (ReportFilters).
     */
    private function operationsSection(ReportFilters $f): array
    {
        // Ciro sayılan (kapanan) adisyonlar üzerinden tek geçişli toplamlar.
        // Servis süresi (dk): TIMESTAMPDIFF MySQL'e özgü → SQLite'ta patlar. Sürücü-
        // bağımsız dakika ifadesi (ReportFilters::minutesExpr; julianday/TIMESTAMPDIFF).
        $minutes = $f->minutesExpr('orders.placed_at', 'orders.closed_at');

        $agg = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->selectRaw(
                'COUNT(*) AS orders, '.
                'COALESCE(SUM(orders.guest_count), 0) AS covers, '.
                'COALESCE(SUM(orders.total_minor), 0) AS revenue, '.
                'AVG(CASE WHEN orders.placed_at IS NOT NULL AND orders.closed_at IS NOT NULL '.
                '  AND orders.closed_at >= orders.placed_at '.
                "  THEN {$minutes} END) AS avg_service_min, ".
                'SUM(CASE WHEN orders.channel = ? THEN 1 ELSE 0 END) AS qr_orders, '.
                'COUNT(DISTINCT CASE WHEN orders.table_id IS NOT NULL THEN orders.table_id END) AS tables_used, '.
                'SUM(CASE WHEN orders.table_id IS NOT NULL THEN 1 ELSE 0 END) AS table_orders',
                [OrderChannel::Qr->value]
            )
            ->first();

        $cancelled = (int) $f->apply(DB::table('orders'), 'orders', 'cancelled_at')
            ->where('orders.status', 'cancelled')
            ->count();

        $orders = (int) ($agg->orders ?? 0);
        $covers = (int) ($agg->covers ?? 0);
        $revenue = (int) ($agg->revenue ?? 0);
        $qrOrders = (int) ($agg->qr_orders ?? 0);
        $tablesUsed = (int) ($agg->tables_used ?? 0);
        $tableOrders = (int) ($agg->table_orders ?? 0);
        $avgServiceMin = $agg->avg_service_min !== null ? (int) round((float) $agg->avg_service_min) : null;

        // En yoğun saat + en iyi gün (mevcut serilerden; ek sorgu yok).
        $peakHour = null;
        foreach ($this->byHour($f) as $h) {
            if ($h['orders'] > 0 && ($peakHour === null || $h['orders'] > $peakHour['orders'])) {
                $peakHour = ['hour' => $h['hour'], 'orders' => $h['orders']];
            }
        }
        $bestDay = null;
        foreach ($this->byDay($f) as $d) {
            if ($d['revenue_minor'] > 0 && ($bestDay === null || $d['revenue_minor'] > $bestDay['revenue_minor'])) {
                $bestDay = ['date' => $d['date'], 'revenue_minor' => $d['revenue_minor']];
            }
        }

        return [
            'covers' => $covers,
            'revenue_per_guest_minor' => $covers > 0 ? (int) round($revenue / $covers) : null,
            'avg_service_min' => $avgServiceMin,
            'table_turnover' => $tablesUsed > 0 ? round($tableOrders / $tablesUsed, 1) : null,
            'qr_share' => $orders > 0 ? round($qrOrders * 100 / $orders, 1) : null,
            'qr_orders' => $qrOrders,
            'cancellation_rate' => ($orders + $cancelled) > 0
                ? round($cancelled * 100 / ($orders + $cancelled), 1)
                : null,
            'cancelled_orders' => $cancelled,
            'peak_hour' => $peakHour,
            'best_day' => $bestDay,
        ];
    }

    /* ---------------- Satış (ciro + önceki döneme kıyas) ---------------- */

    /** Ciro / sipariş / ortalama adisyon + önceki eşit-uzunluk döneme % kıyas. */
    private function salesSection(ReportFilters $f): array
    {
        $summary = $this->sales->summary($f);
        $cur = $summary['current'];
        $prev = $summary['previous'];

        return [
            'revenue_minor' => (int) $cur['revenue_minor'],
            'orders' => (int) $cur['orders'],
            'avg_basket_minor' => (int) $cur['avg_basket_minor'],
            'cancelled_orders' => (int) $summary['cancelled']['orders'],
            'prev' => [
                'revenue_minor' => (int) $prev['revenue_minor'],
                'orders' => (int) $prev['orders'],
                'avg_basket_minor' => (int) $prev['avg_basket_minor'],
            ],
            'delta_pct' => [
                'revenue' => $this->pct((int) $cur['revenue_minor'], (int) $prev['revenue_minor']),
                'orders' => $this->pct((int) $cur['orders'], (int) $prev['orders']),
                'avg_basket' => $this->pct((int) $cur['avg_basket_minor'], (int) $prev['avg_basket_minor']),
            ],
        ];
    }

    /** Günlük ciro/sipariş serisi (boş günler 0 — SalesReportService::daily). */
    private function byDay(ReportFilters $f): array
    {
        return array_map(static fn (array $d): array => [
            'date' => $d['date'],
            'revenue_minor' => (int) $d['revenue_minor'],
            'orders' => (int) $d['orders'],
        ], $this->sales->daily($f)['days']);
    }

    /** Saatlik dağılım 0-23 (yoğun saatler — SalesReportService::hourly). */
    private function byHour(ReportFilters $f): array
    {
        return array_map(static fn (array $h): array => [
            'hour' => (int) $h['hour'],
            'revenue_minor' => (int) $h['revenue_minor'],
            'orders' => (int) $h['orders'],
        ], $this->sales->hourly($f)['hours']);
    }

    /**
     * Haftanın günü performansı (0=Pzt … 6=Paz) — dönemdeki günlük seriden
     * (tz-doğru) TÜRETİLİR, ek sorgu YOK. Hangi günler daha yoğun/kârlı.
     *
     * @param  array<int, array{date: string, revenue_minor: int, orders: int}>  $byDay
     * @return list<array{weekday: int, revenue_minor: int, orders: int}>
     */
    private function byWeekday(array $byDay): array
    {
        $agg = [];
        for ($d = 0; $d < 7; $d++) {
            $agg[$d] = ['revenue_minor' => 0, 'orders' => 0];
        }

        foreach ($byDay as $day) {
            $wd = (int) Carbon::parse($day['date'])->dayOfWeekIso - 1; // 1..7 → 0..6 (0=Pzt)
            $agg[$wd]['revenue_minor'] += (int) $day['revenue_minor'];
            $agg[$wd]['orders'] += (int) $day['orders'];
        }

        $out = [];
        for ($d = 0; $d < 7; $d++) {
            $out[] = ['weekday' => $d, 'revenue_minor' => $agg[$d]['revenue_minor'], 'orders' => $agg[$d]['orders']];
        }

        return $out;
    }

    /** En çok ciro yapan kategoriler (ilk 6 — SalesReportService::categories). */
    private function topCategories(ReportFilters $f): array
    {
        $rows = $this->sales->categories($f)['rows'];

        return array_map(static fn (array $r): array => [
            'name' => (string) $r['name'],
            'qty' => (int) $r['qty'],
            'revenue_minor' => (int) $r['revenue_minor'],
        ], array_slice($rows, 0, 6));
    }

    /** En çok ciro yapan masalar (ilk 6 — SalesReportService::tables). */
    private function topTables(ReportFilters $f): array
    {
        $rows = $this->sales->tables($f)['rows'];

        return array_map(static fn (array $r): array => [
            'name' => (string) $r['name'],
            'orders' => (int) ($r['orders'] ?? 0),
            'revenue_minor' => (int) $r['revenue_minor'],
        ], array_slice($rows, 0, 6));
    }

    /**
     * İndirim + ikram özeti: dönemdeki kapanan adisyonlarda uygulanan toplam
     * indirim (discount_minor) ve ikram (comp_total_minor) + kaç adisyonda.
     * "Ne kadar veriliyor" yönetsel göstergesi (ciro erozyonu). ŞUBE-GÜVENLİ.
     */
    private function discountsSection(ReportFilters $f): array
    {
        $row = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->selectRaw(
                'COALESCE(SUM(orders.discount_minor), 0) AS disc, '.
                'COALESCE(SUM(orders.comp_total_minor), 0) AS comp, '.
                'SUM(CASE WHEN orders.discount_minor > 0 THEN 1 ELSE 0 END) AS disc_orders, '.
                'SUM(CASE WHEN orders.comp_total_minor > 0 THEN 1 ELSE 0 END) AS comp_orders'
            )
            ->first();

        return [
            'discount_minor' => (int) ($row->disc ?? 0),
            'comp_minor' => (int) ($row->comp ?? 0),
            'discount_orders' => (int) ($row->disc_orders ?? 0),
            'comp_orders' => (int) ($row->comp_orders ?? 0),
        ];
    }

    /* ---------------- Dağılımlar (donut) ---------------- */

    /** Ödeme yöntemi dağılımı (payments — başarılı tahsilatlar). */
    private function paymentMix(ReportFilters $f): array
    {
        $rows = $f->apply(DB::table('payments'), 'payments', 'paid_at')
            ->whereIn('payments.status', ['succeeded', 'partially_refunded', 'refunded'])
            ->where('payments.kind', 'payment')
            ->selectRaw('payments.method AS method, COUNT(*) AS c, COALESCE(SUM(payments.amount_minor), 0) AS amount')
            ->groupBy('payments.method')
            ->orderByDesc('amount')
            ->get();

        $total = (int) $rows->sum('amount');

        return [
            'total_minor' => $total,
            'rows' => $rows->map(static fn ($r): array => [
                'method' => (string) $r->method,
                'label' => PaymentMethod::tryFrom((string) $r->method)?->label() ?? (string) $r->method,
                'count' => (int) $r->c,
                'amount_minor' => (int) $r->amount,
                'share' => $total > 0 ? round(((int) $r->amount) * 100 / $total, 1) : 0.0,
            ])->all(),
        ];
    }

    /**
     * Servis tipi dağılımı (Masada / Gel-al / Paket). service_type NULL olan
     * eski kayıtlar kanaldan makul biçimde türetilir (tek kaynak: ServiceType).
     */
    private function serviceTypes(ReportFilters $f): array
    {
        $rows = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->selectRaw('orders.service_type AS service_type, orders.channel AS channel, COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t')
            ->groupBy('orders.service_type', 'orders.channel')
            ->get();

        /** @var array<string, array{orders: int, revenue_minor: int}> $buckets */
        $buckets = [];
        foreach (ServiceType::cases() as $case) {
            $buckets[$case->value] = ['orders' => 0, 'revenue_minor' => 0];
        }

        foreach ($rows as $r) {
            $type = ServiceType::tryFrom((string) $r->service_type)
                ?? ServiceType::fromChannel(OrderChannel::tryFrom((string) $r->channel) ?? OrderChannel::Table);
            $buckets[$type->value]['orders'] += (int) $r->c;
            $buckets[$type->value]['revenue_minor'] += (int) $r->t;
        }

        $total = array_sum(array_column($buckets, 'revenue_minor'));

        $out = [];
        foreach ($buckets as $value => $agg) {
            $out[] = [
                'type' => $value,
                'label' => ServiceType::from($value)->label(),
                'orders' => $agg['orders'],
                'revenue_minor' => $agg['revenue_minor'],
                'share' => $total > 0 ? round($agg['revenue_minor'] * 100 / $total, 1) : 0.0,
            ];
        }

        return ['total_minor' => (int) $total, 'rows' => $out];
    }

    /** En çok satan ürünler (adet bazlı, top 8 — SalesReportService::products). */
    private function topProducts(ReportFilters $f): array
    {
        $rows = $this->sales->products($f)['rows'];

        return array_map(static fn (array $r): array => [
            'name' => (string) $r['name'],
            'qty' => (int) $r['qty'],
            'revenue_minor' => (int) $r['revenue_minor'],
        ], array_slice($rows, 0, 8));
    }

    /* ---------------- Açık adisyon / masa / borç ---------------- */

    /** Açık adisyon + açık masa + açık masa tutarı + açık borç (receivables). */
    private function openSection(ReportFilters $f, int $tenantId, ?int $branchId): array
    {
        $open = $this->sales->openAmount($f);

        // Açık masa: açık adisyonu olan farklı masa sayısı (anlık — occupancy deseni).
        $tableQuery = DB::table('orders')
            ->where('orders.tenant_id', $tenantId)
            ->whereNotIn('orders.status', self::OPEN_EXCLUDED)
            ->whereNotNull('orders.table_id');
        if ($branchId !== null) {
            $tableQuery->where('orders.branch_id', $branchId);
        }
        $openTables = (int) $tableQuery->distinct()->count('orders.table_id');

        // Açık borç (cari): yalnız Borçlar özelliği açıksa. Bakiye >= 0 önbelleği.
        $receivables = ['count' => 0, 'total_minor' => 0, 'enabled' => false];
        if (Features::enabled($tenantId, 'receivables')) {
            $rq = DB::table('receivables')
                ->where('receivables.tenant_id', $tenantId)
                ->where('receivables.balance_minor', '>', 0);
            if ($branchId !== null) {
                $rq->where('receivables.branch_id', $branchId);
            }
            $row = $rq->selectRaw('COUNT(*) AS c, COALESCE(SUM(receivables.balance_minor), 0) AS t')->first();
            $receivables = [
                'count' => (int) ($row->c ?? 0),
                'total_minor' => (int) ($row->t ?? 0),
                'enabled' => true,
            ];
        }

        return [
            'open_orders' => (int) $open['orders'],
            'open_amount_minor' => (int) $open['total_minor'],
            'open_tables' => $openTables,
            'receivables' => $receivables,
        ];
    }

    /* ---------------- Personel performans + prim ---------------- */

    /**
     * Personel performans özeti (ciro/sipariş) + prim toplamı. ŞUBE-GÜVENLİ
     * CommissionService::report'tan derlenir (kullanıcı kümesi geçerli şubeye
     * süzülür); tek çağrıyla hem satış hem prim gelir. En çok satan ilk 5.
     */
    private function staffSection(ReportFilters $f, ?int $branchId): array
    {
        $report = $this->commission->report(
            Carbon::instance($f->fromUtc),
            Carbon::instance($f->toUtc),
            $branchId,
        );

        // PRİM eklentisi kapalıysa prim RAKAMLARINI sızdırma (denetim #9): satış
        // performansı gösterilir ama komisyon 0'lanır (kapalı özelliğin çıktısı çıkmaz).
        $commissionOn = Features::enabled($f->tenantId, 'commission');

        $rows = $report['rows'];
        usort($rows, static fn (array $a, array $b): int => (int) $b['sales_minor'] <=> (int) $a['sales_minor']);

        $top = array_map(static fn (array $r): array => [
            'user' => $r['user'],
            'sales_minor' => (int) $r['sales_minor'],
            'order_count' => (int) $r['order_count'],
            'commission_minor' => $commissionOn ? (int) $r['commission_minor'] : 0,
        ], array_slice($rows, 0, 5));

        return [
            'rows' => $top,
            'commission_enabled' => $commissionOn,
            'commission_total_minor' => $commissionOn ? (int) $report['totals']['commission_minor'] : 0,
            'sales_total_minor' => (int) $report['totals']['sales_minor'],
        ];
    }

    /* ---------------- Canlı mesai / bugünkü plan ---------------- */

    /**
     * ŞU AN mesaide olan personel: açık time_entry'si olanlar (clock_out_at
     * null / status=open). Kiracı süzgeci TenantScope ile otomatik; şube
     * geçerli şubeyle sınırlanır. N+1 yok — user + shift eager-load.
     * Pozisyon önce planlanan vardiyadan, yoksa personel kartından okunur.
     *
     * @return list<array<string, mixed>>
     */
    private function onShiftSection(?int $branchId): array
    {
        $now = Carbon::now();

        $query = TimeEntry::query()
            ->where('status', TimeEntry::STATUS_OPEN)
            ->whereNull('clock_out_at')
            ->with([
                'user:id,name,first_name,last_name,position',
                'shift:id,position',
            ])
            ->orderBy('clock_in_at');

        if ($branchId !== null) {
            $query->where('branch_id', $branchId);
        }

        return $query->get()->map(function (TimeEntry $e) use ($now): array {
            $since = $e->clock_in_at;

            return [
                'name' => $this->displayName($e->user),
                'position' => $e->shift?->position ?? $e->user?->position,
                'since' => $since->toIso8601String(),
                'worked_minutes' => max(0, (int) $since->diffInMinutes($now)),
            ];
        })->all();
    }

    /**
     * BUGÜN henüz başlamamış planlı vardiyalar: starts_at > şimdi ve bugünün
     * (şube saat dilimi) sonuna kadar. Kim, kaçta işbaşı yapacak. Kiracı
     * süzgeci TenantScope ile otomatik; şube geçerli şubeyle sınırlanır.
     *
     * @return list<array<string, mixed>>
     */
    private function upcomingTodaySection(?int $branchId, string $timezone): array
    {
        $now = Carbon::now();
        $endOfToday = Carbon::now($timezone)->endOfDay();

        $query = Shift::query()
            ->where('starts_at', '>', $now)
            ->where('starts_at', '<=', $endOfToday)
            ->with(['user:id,name,first_name,last_name,position'])
            ->orderBy('starts_at');

        if ($branchId !== null) {
            $query->where('branch_id', $branchId);
        }

        return $query->get()->map(fn (Shift $s): array => [
            'name' => $this->displayName($s->user),
            'position' => $s->position ?? $s->user?->position,
            'start' => $s->starts_at->toIso8601String(),
        ])->all();
    }

    /* ---------------- Düşük stok uyarısı ---------------- */

    /**
     * Düşük/kritik stok özeti (Stok özelliği açıksa). Hafif sorgu: kalem
     * eldeki miktarı min/kritik eşiğinin altındaysa listelenir; ilk 6 satır +
     * sayaçlar. Özellik kapalıysa null (ekran bölümü hiç render edilmez).
     */
    private function inventorySection(int $tenantId): ?array
    {
        if (! InventoryFeature::enabled($tenantId)) {
            return null;
        }

        $items = DB::table('inv_items')
            ->where('tenant_id', $tenantId)
            ->where('is_active', true)
            ->get(['id', 'name', 'base_unit', 'min_qty_milli', 'critical_qty_milli']);

        if ($items->isEmpty()) {
            return ['critical' => 0, 'low' => 0, 'rows' => []];
        }

        $onHand = DB::table('inv_stock_levels')
            ->where('tenant_id', $tenantId)
            ->selectRaw('item_id, COALESCE(SUM(qty_milli), 0) AS total')
            ->groupBy('item_id')
            ->pluck('total', 'item_id');

        $rows = [];
        $criticalCount = 0;
        $lowCount = 0;

        foreach ($items as $item) {
            $current = (int) ($onHand[$item->id] ?? 0);
            $min = (int) $item->min_qty_milli;
            $critical = (int) $item->critical_qty_milli;

            if ($critical > 0 && $current <= $critical) {
                $severity = 'critical';
                $criticalCount++;
            } elseif ($min > 0 && $current <= $min) {
                $severity = 'low';
                $lowCount++;
            } else {
                continue;
            }

            $rows[] = [
                'item_id' => (int) $item->id,
                'name' => (string) $item->name,
                'severity' => $severity,
                'on_hand' => Qty::toDecimalString($current),
                'threshold' => Qty::toDecimalString($critical > 0 ? $critical : $min),
                'unit' => (string) $item->base_unit,
            ];
        }

        // Kritik önce, sonra düşük; ekrana ilk 6.
        usort($rows, static fn (array $a, array $b): int => strcmp($a['severity'], $b['severity']));

        return [
            'critical' => $criticalCount,
            'low' => $lowCount,
            'rows' => array_slice($rows, 0, 6),
        ];
    }

    /* ---------------- Teslimat özeti ---------------- */

    /**
     * Teslimat durum özeti (Teslimat özelliği açıksa). Dönem içi (created_at)
     * kayıtlar duruma göre sayılır. Özellik kapalıysa null (bölüm atlanır).
     */
    private function deliverySection(ReportFilters $f, int $tenantId, ?int $branchId): ?array
    {
        if (! Features::enabled($tenantId, 'delivery')) {
            return null;
        }

        $query = DB::table('order_deliveries')
            ->where('order_deliveries.tenant_id', $tenantId)
            ->where('order_deliveries.created_at', '>=', $f->fromUtc)
            ->where('order_deliveries.created_at', '<', $f->toUtc);
        if ($branchId !== null) {
            $query->where('order_deliveries.branch_id', $branchId);
        }

        $counts = $query
            ->selectRaw('order_deliveries.status AS status, COUNT(*) AS c')
            ->groupBy('order_deliveries.status')
            ->pluck('c', 'status');

        $get = static fn (string $s): int => (int) ($counts[$s] ?? 0);

        return [
            'pending' => $get('pending'),
            'assigned' => $get('assigned'),
            'on_the_way' => $get('on_the_way'),
            'delivered' => $get('delivered'),
            'failed' => $get('failed'),
            'total' => (int) $counts->sum(),
        ];
    }

    /* ---------------- Yardımcı ---------------- */

    /** Personel görünen adı (name kolonu; yoksa ad+soyad — boş string dönmez). */
    private function displayName(mixed $user): string
    {
        if ($user === null) {
            return '—';
        }

        $name = trim((string) ($user->name ?? ''));
        if ($name !== '') {
            return $name;
        }

        $composed = trim(((string) ($user->first_name ?? '')).' '.((string) ($user->last_name ?? '')));

        return $composed !== '' ? $composed : '—';
    }

    /** Önceki döneme göre yüzde değişim; payda 0 ise null (uydurma % yok). */
    private function pct(int $current, int $previous): ?float
    {
        if ($previous <= 0) {
            return null;
        }

        return round(($current - $previous) * 100 / $previous, 1);
    }
}
