<?php

namespace App\Modules\Reports\Services;

use App\Modules\Payments\Enums\PaymentMethod;
use App\Modules\Reports\Support\ReportFilters;
use Illuminate\Support\Facades\DB;

/**
 * Finans raporları. Kaynaklar:
 * - Ciro/brüt-net satış YALNIZ KAPANAN (paid/debt_transferred) adisyonlardan
 *   hesaplanır (bkz. SalesReportService docblock — açık adisyonlar Ciro'ya
 *   sayılmaz, tek tanım kaynağı orada).
 * - Tahsilat için TEK DOĞRULUK KAYNAĞI `payments` (ADR-010); adisyon
 *   tutarları `orders` döküm alanlarından okunur (OrderService tek yerde
 *   hesaplar, rapor yeniden HESAPLAMAZ).
 * - Tutarlar kuruş-integer (ADR-007).
 */
class FinanceReportService
{
    /** Ciro'ya sayılan KAPANAN durumlar (bkz. SalesReportService — tek tanım). */
    private const REVENUE_STATUSES = ['paid', 'debt_transferred'];

    /** Brüt/net satış (KAPANAN adisyonlar) + indirim/ikram/iptal/iade/servis bedeli/bahşiş özeti. */
    public function summary(ReportFilters $f): array
    {
        $sales = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->selectRaw(
                'COUNT(*) AS orders_count,
                 COALESCE(SUM(orders.items_total_minor), 0) AS items_total,
                 COALESCE(SUM(orders.discount_minor), 0) AS order_discount,
                 COALESCE(SUM(orders.comp_total_minor), 0) AS comp_total,
                 COALESCE(SUM(orders.vat_total_minor), 0) AS vat_total,
                 COALESCE(SUM(orders.service_charge_minor), 0) AS service_charge,
                 COALESCE(SUM(orders.rounding_minor), 0) AS rounding,
                 COALESCE(SUM(orders.total_minor), 0) AS grand_total,
                 COALESCE(SUM(orders.refunded_minor), 0) AS refunded'
            )->first();

        // Satır düzeyi indirimler (adisyon indiriminden ayrı alan).
        $itemDiscount = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.status', '!=', 'cancelled')
            ->sum('order_items.discount_minor');

        $cancelled = $f->apply(DB::table('orders'), 'orders')
            ->where('orders.status', 'cancelled')
            ->selectRaw('COUNT(*) AS c, COALESCE(SUM(orders.total_minor), 0) AS t')
            ->first();

        // Tahsilat + bahşiş: payments (paid_at aralıkta, başarılı aile).
        $collected = $this->paymentsBase($f)
            ->where('payments.kind', 'payment')
            ->selectRaw(
                'COUNT(*) AS c,
                 COALESCE(SUM(payments.amount_minor), 0) AS amount,
                 COALESCE(SUM(payments.tip_minor), 0) AS tips'
            )->first();

        $refundRows = $this->paymentsBase($f)
            ->where('payments.kind', 'refund')
            ->selectRaw('COUNT(*) AS c, COALESCE(SUM(payments.amount_minor), 0) AS amount')
            ->first();

        $grand = (int) $sales->grand_total;
        $vat = (int) $sales->vat_total;

        return [
            'orders' => (int) $sales->orders_count,
            'gross_minor' => $grand,                       // KDV dahil satış
            'net_minor' => $grand - $vat,                  // KDV hariç satış
            'vat_minor' => $vat,
            'items_total_minor' => (int) $sales->items_total,
            'order_discount_minor' => (int) $sales->order_discount,
            'item_discount_minor' => (int) $itemDiscount,
            'comp_minor' => (int) $sales->comp_total,
            'service_charge_minor' => (int) $sales->service_charge,
            'rounding_minor' => (int) $sales->rounding,
            'cancelled_orders' => (int) $cancelled->c,
            'cancelled_minor' => (int) $cancelled->t,
            'refunded_minor' => (int) $sales->refunded,
            'collected_count' => (int) $collected->c,
            'collected_minor' => (int) $collected->amount,
            'tips_minor' => (int) $collected->tips,
            'refund_payments_count' => (int) $refundRows->c,
            'refund_payments_minor' => (int) $refundRows->amount,
        ];
    }

    /** KDV oranı kırılımı (KAPANAN adisyonlar, kalem snapshot'ındaki oranla — satış anı esas). */
    public function vat(ReportFilters $f): array
    {
        $rows = $f->apply(DB::table('orders'), 'orders')
            ->whereIn('orders.status', self::REVENUE_STATUSES)
            ->join('order_items', 'order_items.order_id', '=', 'orders.id')
            ->where('order_items.status', '!=', 'cancelled')
            ->selectRaw(
                'order_items.tax_rate AS rate,
                 COALESCE(SUM(order_items.line_total_minor), 0) AS gross,
                 COALESCE(SUM(order_items.vat_minor), 0) AS vat'
            )
            ->groupBy('order_items.tax_rate')
            ->orderBy('order_items.tax_rate')
            ->get();

        return [
            'rows' => $rows->map(fn ($r) => [
                'rate' => (float) $r->rate,
                'gross_minor' => (int) $r->gross,
                'vat_minor' => (int) $r->vat,
                'net_minor' => (int) $r->gross - (int) $r->vat,
            ])->all(),
        ];
    }

    /** Ödeme yöntemi kırılımı (başarılı tahsilatlar) + iade satırı. */
    public function paymentMethods(ReportFilters $f): array
    {
        $rows = $this->paymentsBase($f)
            ->where('payments.kind', 'payment')
            ->selectRaw(
                'payments.method AS method,
                 COUNT(*) AS c,
                 COALESCE(SUM(payments.amount_minor), 0) AS amount,
                 COALESCE(SUM(payments.tip_minor), 0) AS tips'
            )
            ->groupBy('payments.method')
            ->orderByDesc('amount')
            ->get();

        $total = (int) $rows->sum('amount');

        $refunds = $this->paymentsBase($f)
            ->where('payments.kind', 'refund')
            ->selectRaw('payments.method AS method, COUNT(*) AS c, COALESCE(SUM(payments.amount_minor), 0) AS amount')
            ->groupBy('payments.method')
            ->get();

        return [
            'total_minor' => $total,
            'rows' => $rows->map(fn ($r) => [
                'method' => (string) $r->method,
                'label' => PaymentMethod::tryFrom((string) $r->method)?->label() ?? (string) $r->method,
                'count' => (int) $r->c,
                'amount_minor' => (int) $r->amount,
                'tips_minor' => (int) $r->tips,
                'share' => $total > 0 ? round(((int) $r->amount) * 100 / $total, 1) : 0.0,
            ])->all(),
            'refunds' => $refunds->map(fn ($r) => [
                'method' => (string) $r->method,
                'label' => PaymentMethod::tryFrom((string) $r->method)?->label() ?? (string) $r->method,
                'count' => (int) $r->c,
                'amount_minor' => (int) $r->amount,
            ])->all(),
        ];
    }

    /** Kasa oturumları: Z no, beklenen/sayılan nakit, FARK. */
    public function cashSessions(ReportFilters $f): array
    {
        $rows = $f->apply(DB::table('cash_sessions'), 'cash_sessions', 'opened_at')
            ->leftJoin('cash_registers', 'cash_registers.id', '=', 'cash_sessions.cash_register_id')
            ->leftJoin('users AS openers', 'openers.id', '=', 'cash_sessions.opened_by_id')
            ->orderByDesc('cash_sessions.opened_at')
            ->limit(100)
            ->get([
                'cash_sessions.id', 'cash_sessions.z_number', 'cash_sessions.status',
                'cash_sessions.opened_at', 'cash_sessions.closed_at',
                'cash_sessions.opening_float_minor', 'cash_sessions.expected_cash_minor',
                'cash_sessions.counted_cash_minor', 'cash_sessions.difference_minor',
                'cash_registers.name AS register_name',
                'openers.name AS opened_by',
            ]);

        return [
            'rows' => $rows->map(fn ($r) => [
                'id' => (int) $r->id,
                'z_number' => (int) $r->z_number,
                'status' => (string) $r->status,
                'register' => (string) ($r->register_name ?? '—'),
                'opened_by' => $r->opened_by !== null ? (string) $r->opened_by : null,
                'opened_at' => $r->opened_at,
                'closed_at' => $r->closed_at,
                'opening_float_minor' => (int) $r->opening_float_minor,
                'expected_minor' => $r->expected_cash_minor !== null ? (int) $r->expected_cash_minor : null,
                'counted_minor' => $r->counted_cash_minor !== null ? (int) $r->counted_cash_minor : null,
                'difference_minor' => $r->difference_minor !== null ? (int) $r->difference_minor : null,
            ])->all(),
        ];
    }

    /** Açık masa/hesap + açık hesap tahsilatları (bakiyesi kalan, HENÜZ KAPANMAMIŞ adisyonlar — Ciro DEĞİLDİR). */
    public function openAccounts(ReportFilters $f): array
    {
        // Bakiye kalan (kapanmamış) adisyonlar — anlık durum, tarih filtresi
        // yalnız açılış tarihini sınırlar. `debt_transferred` KAPANMIŞTIR
        // (masa boşalır, bakiye artık cari borcuna taşınmıştır — bkz.
        // ReceivablesReportService) — bu listede DEĞİL, açık borçtadır.
        $open = $f->apply(DB::table('orders'), 'orders')
            ->whereNotIn('orders.status', ['draft', 'cancelled', 'paid', 'refunded', 'debt_transferred'])
            ->whereRaw('orders.total_minor > orders.paid_minor')
            ->leftJoin('tables', 'tables.id', '=', 'orders.table_id')
            ->orderByDesc('orders.created_at')
            ->limit(200)
            ->get([
                'orders.id', 'orders.status', 'orders.channel', 'orders.created_at',
                'orders.total_minor', 'orders.paid_minor', 'orders.customer_name',
                'tables.name AS table_name',
            ]);

        $onAccount = $this->paymentsBase($f)
            ->where('payments.kind', 'payment')
            ->where('payments.method', 'on_account')
            ->selectRaw('COUNT(*) AS c, COALESCE(SUM(payments.amount_minor), 0) AS amount')
            ->first();

        return [
            'open_orders' => $open->map(fn ($r) => [
                'id' => (int) $r->id,
                'status' => (string) $r->status,
                'channel' => (string) $r->channel,
                'table' => $r->table_name !== null ? (string) $r->table_name : null,
                'customer' => $r->customer_name !== null ? (string) $r->customer_name : null,
                'created_at' => $r->created_at,
                'total_minor' => (int) $r->total_minor,
                'paid_minor' => (int) $r->paid_minor,
                'balance_minor' => (int) $r->total_minor - (int) $r->paid_minor,
            ])->all(),
            'on_account' => [
                'count' => (int) $onAccount->c,
                'amount_minor' => (int) $onAccount->amount,
            ],
        ];
    }

    /**
     * Mutabakat: "kasada ne olmalı (nakit), POS ne diyor (kart), sistemin
     * adisyon defteri ne diyor" TEK ekranda.
     *
     * - Nakit / POS(kart) / diğer yöntemler: `payments` (TEK DOĞRULUK
     *   KAYNAĞI, ADR-010), paid_at aralığında.
     * - "Sistemdeki adisyon toplamı": bu aralıkta KAPANAN (closed_at)
     *   adisyonların `orders.paid_minor` toplamı — orders.paid_minor
     *   ZATEN payments'tan türetilir (OrderService, elle set edilmez),
     *   yani bu iki taraf NORMALDE eşittir. `payments` paid_at, `orders`
     *   closed_at kullanır; aynı işlem genelde aynı anda gerçekleşir ama
     *   TAM aynı milisaniyede olmayabilir — dönem sınırına denk gelen
     *   birkaç kuruşluk fark BEKLENEBİLİR ve dürüstçe gösterilir (uydurma
     *   sıfır yok). Sistemli/büyük fark gerçek bir tutarsızlığa işaret eder.
     * - Kasa sayımı (varsa): bu aralıkta KAPANAN kasa oturumlarının
     *   beklenen/sayılan nakit toplamı ve farkı (cash_sessions — zaten
     *   kayıt anında hesaplanır, burada yeniden hesaplanmaz).
     */
    public function reconciliation(ReportFilters $f): array
    {
        $byMethod = $this->paymentsBase($f)
            ->where('payments.kind', 'payment')
            ->selectRaw('payments.method AS method, COUNT(*) AS c, COALESCE(SUM(payments.amount_minor), 0) AS amount')
            ->groupBy('payments.method')
            ->get()
            ->keyBy('method');

        $posMethods = ['credit_card', 'debit_card'];
        $cashMinor = (int) ($byMethod->get('cash')->amount ?? 0);
        $cashCount = (int) ($byMethod->get('cash')->c ?? 0);

        $posMinor = 0;
        $posCount = 0;
        foreach ($posMethods as $m) {
            $posMinor += (int) ($byMethod->get($m)->amount ?? 0);
            $posCount += (int) ($byMethod->get($m)->c ?? 0);
        }

        $otherMinor = 0;
        $otherCount = 0;
        foreach ($byMethod as $method => $row) {
            if ($method === 'cash' || in_array($method, $posMethods, true)) {
                continue;
            }
            $otherMinor += (int) $row->amount;
            $otherCount += (int) $row->c;
        }

        $paymentsTotalMinor = $cashMinor + $posMinor + $otherMinor;

        // Sistemin adisyon defteri: bu aralıkta KAPANAN adisyonlar.
        $ordersClosed = $f->apply(DB::table('orders'), 'orders', 'closed_at')
            ->whereNotNull('orders.closed_at')
            ->selectRaw(
                'COUNT(*) AS c,
                 COALESCE(SUM(orders.total_minor), 0) AS total,
                 COALESCE(SUM(orders.paid_minor), 0) AS paid'
            )->first();

        $ordersPaidMinor = (int) $ordersClosed->paid;

        // Kasa sayımı: bu aralıkta KAPANAN (Z alınmış) oturumlar.
        $sessions = $f->apply(DB::table('cash_sessions'), 'cash_sessions', 'closed_at')
            ->where('cash_sessions.status', 'closed')
            ->selectRaw(
                'COUNT(*) AS c,
                 COALESCE(SUM(cash_sessions.expected_cash_minor), 0) AS expected,
                 COALESCE(SUM(cash_sessions.counted_cash_minor), 0) AS counted,
                 COALESCE(SUM(cash_sessions.difference_minor), 0) AS diff'
            )->first();

        return [
            'from' => $f->from,
            'to' => $f->to,
            'cash_minor' => $cashMinor,
            'cash_count' => $cashCount,
            'pos_minor' => $posMinor,
            'pos_count' => $posCount,
            'other_minor' => $otherMinor,
            'other_count' => $otherCount,
            'payments_total_minor' => $paymentsTotalMinor,
            'orders_closed_count' => (int) $ordersClosed->c,
            'orders_total_minor' => (int) $ordersClosed->total,
            'orders_paid_minor' => $ordersPaidMinor,
            'difference_minor' => $paymentsTotalMinor - $ordersPaidMinor,
            'cash_sessions_closed_count' => (int) $sessions->c,
            'cash_sessions_expected_minor' => (int) $sessions->expected,
            'cash_sessions_counted_minor' => (int) $sessions->counted,
            'cash_sessions_difference_minor' => (int) $sessions->diff,
            'has_cash_sessions' => (int) $sessions->c > 0,
        ];
    }

    /** Başarılı ödeme ailesi; aralık paid_at üzerinden. */
    private function paymentsBase(ReportFilters $f): \Illuminate\Database\Query\Builder
    {
        return $f->apply(DB::table('payments'), 'payments', 'paid_at')
            ->whereIn('payments.status', ['succeeded', 'partially_refunded', 'refunded']);
    }
}
