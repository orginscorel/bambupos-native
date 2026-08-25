/**
 * Raporlar modülü — tipler + veri erişimi + ortak yardımcılar.
 * Veri /api/v1/reports uçlarından gelir; tutarlar kuruş-integer'dır ve
 * yalnız görüntülenirken biçimlenir (ADR-007).
 */
import './viz.css';
import { ref, watch, type Ref } from 'vue';
import { api, ApiError } from '@/lib/http';

/* ---------------------------------- Tipler --------------------------------- */

export interface ReportFilterState {
    from: string;
    to: string;
    // ŞUBE KAPSAMI: raporlar aktif şubeyi izler ("tümü/all" YOK). branch_id
    // istekte gönderilse de backend geçerli şubeyle süzer.
    branchId: number | null;
}

export interface PeriodTotals {
    orders: number;
    revenue_minor: number;
    avg_basket_minor: number;
    guests: number;
    per_guest_minor: number | null;
}

export interface SalesSummary {
    current: PeriodTotals;
    previous: PeriodTotals;
    cancelled: { orders: number; total_minor: number };
}

export interface DayPoint {
    date: string;
    orders: number;
    revenue_minor: number;
    avg_basket_minor: number;
}

export interface HourPoint {
    hour: number;
    orders: number;
    revenue_minor: number;
}

export interface NamedSalesRow {
    name: string;
    qty: number;
    revenue_minor: number;
    orders: number;
}

export interface ProductsReport {
    rows: NamedSalesRow[];
    top_by_qty: NamedSalesRow[];
    least_by_qty: NamedSalesRow[];
}

export interface ChannelRow {
    channel: string;
    label: string;
    orders: number;
    revenue_minor: number;
    share: number;
}

export interface TableSalesRow {
    name: string;
    orders: number;
    revenue_minor: number;
    turns: number;
    avg_minutes: number | null;
}

export interface FinanceSummary {
    orders: number;
    gross_minor: number;
    net_minor: number;
    vat_minor: number;
    items_total_minor: number;
    order_discount_minor: number;
    item_discount_minor: number;
    comp_minor: number;
    service_charge_minor: number;
    rounding_minor: number;
    cancelled_orders: number;
    cancelled_minor: number;
    refunded_minor: number;
    collected_count: number;
    collected_minor: number;
    tips_minor: number;
    refund_payments_count: number;
    refund_payments_minor: number;
}

export interface PaymentMethodRow {
    method: string;
    label: string;
    count: number;
    amount_minor: number;
    tips_minor: number;
    share: number;
}

/**
 * İkram (comp) özeti: gelir getirmeyen ama stok/maliyet tüketen kalemler.
 * `value_minor` = orders.comp_total_minor (bedelsiz değer),
 * `cost_minor` = tüketilen maliyet (yalnız maliyeti bilinen ürünler).
 */
export interface CompSummary {
    qty: number;
    items: number;
    value_minor: number;
    cost_minor: number;
    cost_known_items: number;
    missing_cost_items: number;
}

export interface ProfitReport {
    rows: ProfitRow[];
    missing_cost_count: number;
    median_margin: number | null;
    comp: CompSummary;
}

export interface ProfitRow {
    name: string;
    qty: number;
    revenue_minor: number;
    net_minor: number;
    unit_cost_minor: number | null;
    cost_minor: number | null;
    profit_minor: number | null;
    margin: number | null;
    has_cost: boolean;
    high_volume_low_margin: boolean;
}

export interface EodSummary {
    from: string;
    to: string;
    orders: number;
    revenue_minor: number;
    avg_basket_minor: number;
    guests: number;
    per_guest_minor: number | null;
    orders_opened: number;
    orders_closed: number;
    order_discount_minor: number;
    item_discount_minor: number;
    discount_total_minor: number;
    comp_minor: number;
    comp_count: number;
    comp_items: number;
    comp_cost_minor: number;
    comp_cost_known_items: number;
    comp_missing_cost_items: number;
    debt_transferred_count: number;
    debt_transferred_minor: number;
    debt_transferred_balance_minor: number;
    cancelled_orders: number;
    cancelled_minor: number;
    refunded_minor: number;
    refund_payments_count: number;
    refund_payments_minor: number;
    collected_minor: number;
    collected_count: number;
    tips_minor: number;
    open_receivables_available: boolean;
    open_receivables_count: number;
    open_receivables_total_minor: number | null;
    open_table_orders: number;
    open_table_minor: number;
}

export interface ReceivablesRow {
    name: string;
    phone: string | null;
    balance_minor: number;
}

export interface ReceivablesReport {
    available: boolean;
    rows: ReceivablesRow[];
    total_minor: number | null;
    count: number;
}

export interface ReconciliationSummary {
    from: string;
    to: string;
    cash_minor: number;
    cash_count: number;
    pos_minor: number;
    pos_count: number;
    other_minor: number;
    other_count: number;
    payments_total_minor: number;
    orders_closed_count: number;
    orders_total_minor: number;
    orders_paid_minor: number;
    difference_minor: number;
    cash_sessions_closed_count: number;
    cash_sessions_expected_minor: number;
    cash_sessions_counted_minor: number;
    cash_sessions_difference_minor: number;
    has_cash_sessions: boolean;
}

/** §11 Komi Teslim SLA: teslim alma → masaya verme logu + ihlaller + komi kırılımı. */
export interface DeliverySlaRow {
    id: number;
    order_id: number;
    item: string;
    table: string | null;
    staff: string;
    picked_up_at: string;
    served_at: string | null;
    duration_minutes: number;
    status: string;
    breached: boolean;
}

export interface DeliverySlaStaffRow {
    name: string;
    deliveries: number;
    breaches: number;
    breach_rate: number;
    avg_duration_minutes: number | null;
}

export interface DeliverySlaReport {
    target_minutes: number;
    total: number;
    breached_count: number;
    breach_rate: number;
    avg_duration_minutes: number | null;
    open_breach_count: number;
    rows: DeliverySlaRow[];
    by_staff: DeliverySlaStaffRow[];
}

export interface ExportRow {
    id: number;
    report: string;
    title: string;
    format: string;
    status: 'queued' | 'processing' | 'done' | 'failed';
    rows_count: number | null;
    error: string | null;
    from: string | null;
    to: string | null;
    created_at: string | null;
    finished_at: string | null;
    download_url: string | null;
}

/* ------------------------------- Veri erişimi ------------------------------ */

function query(filters: ReportFilterState): string {
    const params = new URLSearchParams({ from: filters.from, to: filters.to });
    if (filters.branchId !== null) params.set('branch_id', String(filters.branchId));
    return params.toString();
}

export async function fetchReport<T>(key: string, filters: ReportFilterState): Promise<T> {
    const res = await api<{ data: T }>(`/api/v1/reports/${key}?${query(filters)}`);
    return res.data;
}

export async function fetchExports(): Promise<ExportRow[]> {
    const res = await api<{ exports: ExportRow[] }>('/api/v1/reports/exports');
    return res.exports;
}

export async function requestExport(report: string, format: string, filters: ReportFilterState): Promise<ExportRow> {
    const res = await api<{ export: ExportRow }>(`/api/v1/reports/exports?${query(filters)}`, {
        method: 'POST',
        body: { report, format },
    });
    return res.export;
}

/**
 * Rapor verisi yükleyici: filtre değişince yeniden çeker.
 * Yeniden yüklemede eski görünüm düşük opaklıkta tutulur (loading bayrağı);
 * iskelet yalnız İLK yüklemede gösterilir.
 */
export function useReport<T>(key: string, filters: Ref<ReportFilterState>) {
    const data = ref<T | null>(null) as Ref<T | null>;
    const loading = ref(false);
    const error = ref('');

    let requestSeq = 0;

    async function reload(): Promise<void> {
        const seq = ++requestSeq;
        loading.value = true;
        error.value = '';
        try {
            const result = await fetchReport<T>(key, filters.value);
            if (seq === requestSeq) data.value = result;
        } catch (e) {
            if (seq === requestSeq) error.value = e instanceof ApiError ? e.displayMessage : 'Rapor yüklenemedi.';
        } finally {
            if (seq === requestSeq) loading.value = false;
        }
    }

    watch(filters, () => void reload(), { deep: true, immediate: true });

    return { data, loading, error, reload };
}

/* ------------------------------ Ortak yardımcı ----------------------------- */

/** Kategorik palet CSS değişkeni: sabit sıra, 4'ten sonrası "Diğer" grisi. */
export function seriesColor(index: number): string {
    return index < 4 ? `var(--viz-${index + 1})` : 'var(--viz-other)';
}

/** Yüzde değişim; önceki dönem 0/veri yoksa null (uydurma oran yok). */
export function pctChange(current: number, previous: number): number | null {
    if (previous === 0) return null;
    return Math.round(((current - previous) / previous) * 1000) / 10;
}

/** Bugünden geriye n-1 gün: [from, to] (yerel tarih, YYYY-MM-DD). */
export function lastDays(n: number): { from: string; to: string } {
    const to = new Date();
    const from = new Date();
    from.setDate(to.getDate() - (n - 1));
    return { from: isoDate(from), to: isoDate(to) };
}

export function isoDate(d: Date): string {
    const pad = (v: number) => String(v).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** "21 Tem" gibi kısa gün etiketi. */
export function shortDay(dateStr: string): string {
    return new Date(`${dateStr}T00:00:00`).toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' });
}
