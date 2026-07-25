/**
 * Kasa/ödeme ekranlarının ortak tipleri + API yardımcıları.
 * Enum sözlükleri sunucudan Inertia prop'u gelir (PHP tek kaynak).
 */
import { api, ApiError } from '@/lib/http';

export interface MethodMeta {
    value: string;
    label: string;
    icon: string;
    terminal: boolean;
}

export interface StatusMeta {
    value: string;
    label: string;
    icon: string;
    variant: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
}

export interface MovementTypeMeta {
    value: string;
    label: string;
    direction: 'in' | 'out';
}

export interface PaymentsMeta {
    paymentMethods: MethodMeta[];
    paymentStatuses: StatusMeta[];
    movementTypes: MovementTypeMeta[];
    cashRoundingStep: number;
    canRefund: boolean;
    canCashManage: boolean;
    canCashView: boolean;
}

export function metaFromProps(props: Record<string, unknown>): PaymentsMeta {
    return {
        paymentMethods: (props.paymentMethods as MethodMeta[]) ?? [],
        paymentStatuses: (props.paymentStatuses as StatusMeta[]) ?? [],
        movementTypes: (props.movementTypes as MovementTypeMeta[]) ?? [],
        cashRoundingStep: (props.cashRoundingStep as number) ?? 25,
        canRefund: Boolean(props.canRefund),
        canCashManage: Boolean(props.canCashManage),
        canCashView: Boolean(props.canCashView),
    };
}

export interface PayableOrder {
    id: number;
    table_name: string | null;
    channel_label: string;
    channel_icon: string;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    version: number;
    customer_name: string | null;
    items_count: number;
    items_total_minor: number;
    discount_minor: number;
    service_charge_minor: number;
    rounding_minor: number;
    total_minor: number;
    paid_minor: number;
    refunded_minor: number;
    remaining_minor: number;
    created_at: string | null;
}

/**
 * Adisyon kalemi (OrderPresenter::item). Kasa ekranı ödeme öncesi
 * gözden geçirme/düzeltme için OKUR; hazırlık durumu GÖSTERİLMEZ
 * (tutar odaklı): yalnız ad + adet + birim + satır toplamı.
 */
export interface OrderItemRow {
    id: number;
    qty: number;
    name: string;
    variant_name: string | null;
    unit_price_minor: number;
    options_price_minor: number;
    line_total_minor: number;
    is_comp: boolean;
    comp_reason: string | null;
    is_active: boolean;
    note: string | null;
    options: Array<{ id: number; group_name: string; option_name: string; price_minor: number }>;
}

/** OrderPresenter::detail — kalemli tam adisyon (mevcut Orders ucu). */
export interface OrderDetail {
    id: number;
    version: number;
    table_name: string | null;
    customer_name: string | null;
    channel_label: string;
    guest_count: number | null;
    is_open: boolean;
    status: string;
    payment_state: string;
    items_total_minor: number;
    discount_minor: number;
    comp_total_minor: number;
    service_charge_minor: number;
    rounding_minor: number;
    total_minor: number;
    paid_minor: number;
    remaining_minor: number;
    items: OrderItemRow[];
}

export interface PaymentRow {
    id: number;
    order_id: number;
    reference: string;
    kind: 'payment' | 'refund';
    refund_of_id: number | null;
    method: string;
    method_label: string;
    method_icon: string;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    amount_minor: number;
    tip_minor: number;
    tendered_minor: number | null;
    change_minor: number;
    provider: string | null;
    provider_txn_id: string | null;
    cashier: string | null;
    reason: string | null;
    note: string | null;
    suspect: boolean;
    suspect_reason: string | null;
    refunded_total_minor: number;
    paid_at: string | null;
    created_at: string | null;
}

export interface RegisterRow {
    id: number;
    branch_id: number;
    name: string;
    is_active: boolean;
    open_session: SessionRow | null;
}

export interface SessionRow {
    id: number;
    cash_register_id: number;
    register_name: string | null;
    z_number: number;
    status: 'open' | 'closed';
    opening_float_minor: number;
    opened_by: string | null;
    opened_at: string | null;
    closed_by: string | null;
    closed_at: string | null;
    expected_cash_minor: number | null;
    counted_cash_minor: number | null;
    difference_minor: number | null;
    closing_note: string | null;
}

export interface MovementRow {
    id: number;
    type: string;
    type_label: string;
    direction: 'in' | 'out';
    amount_minor: number;
    reason: string | null;
    payment_id: number | null;
    user: string | null;
    reverses_id: number | null;
    reversed_by_id: number | null;
    created_at: string | null;
}

export interface SessionReport {
    session_id: number;
    z_number: number;
    status: string;
    opened_at: string | null;
    closed_at: string | null;
    opening_float_minor: number;
    expected_cash_minor: number;
    counted_cash_minor: number | null;
    difference_minor: number | null;
    payments_total_minor: number;
    payments_count: number;
    refunds_total_minor: number;
    refunds_count: number;
    voids_total_minor: number;
    voids_count: number;
    tips_total_minor: number;
    discounts_total_minor: number;
    comps_total_minor: number;
    service_charges_total_minor: number;
    by_method: Array<{ method: string; label: string; count: number; collected_minor: number; refunded_minor: number; net_minor: number }>;
    movements: Array<{ type: string; label: string; direction: 'in' | 'out'; total_minor: number; count: number }>;
}

/* ---- API ---- */

export const fetchPendingOrders = (branchId: number | null, q: string) =>
    api<{ orders: PayableOrder[] }>(
        `/api/v1/payments/pending-orders?${branchId ? `branch_id=${branchId}&` : ''}q=${encodeURIComponent(q)}`,
    ).then((r) => r.orders);

export const fetchOrderPayments = (orderId: number) =>
    api<{ order: PayableOrder; payments: PaymentRow[] }>(`/api/v1/orders/${orderId}/payments`);

/** Kalem dökümü (ödeme öncesi gözden geçirme/düzeltme). orders.view gerektirir. */
export const fetchOrderDetail = (orderId: number) =>
    api<{ order: OrderDetail }>(`/api/v1/orders/${orderId}`).then((r) => r.order);

export const fetchRegisters = () => api<{ registers: RegisterRow[] }>('/api/v1/cash/registers').then((r) => r.registers);

export const fetchSessions = (registerId?: number) =>
    api<{ sessions: SessionRow[] }>(`/api/v1/cash/sessions${registerId ? `?register_id=${registerId}` : ''}`).then((r) => r.sessions);

export const fetchSessionDetail = (id: number) =>
    api<{ session: SessionRow; movements: MovementRow[]; report: SessionReport }>(`/api/v1/cash/sessions/${id}`);

export const fetchSessionReport = (id: number) =>
    api<{ session: SessionRow; report: SessionReport }>(`/api/v1/cash/sessions/${id}/report`);

/** Kuruş → "1.234,56". */
export const money = (minor: number): string =>
    (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** "12,50" / "12.5" / "12" → kuruş; geçersizse null. */
export function parseMoney(input: string): number | null {
    const normalized = input.trim().replace(/\./g, input.includes(',') ? '' : '.').replace(',', '.');
    if (normalized === '' || Number.isNaN(Number(normalized))) return null;
    const minor = Math.round(Number(normalized) * 100);
    return minor >= 0 ? minor : null;
}

/** Idempotency-Key üretimi (çift dokunma ödeme çoğaltmasın). */
export function newIdempotencyKey(): string {
    if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
    return `pay-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

/** Idempotency-Key başlıklı POST (paylaşımlı lib/http'ye dokunmadan). */
export async function apiIdempotent<T = unknown>(path: string, body: unknown, key: string): Promise<T> {
    const xsrf = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);

    const response = await fetch(path, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-XSRF-TOKEN': xsrf ? decodeURIComponent(xsrf[1]) : '',
            'Idempotency-Key': key,
        },
        body: JSON.stringify(body),
    });

    let payload: Record<string, unknown> = {};
    try {
        payload = (await response.json()) as Record<string, unknown>;
    } catch {
        /* gövdesiz yanıt */
    }

    if (!response.ok) {
        throw new ApiError(
            response.status,
            typeof payload.message === 'string' ? payload.message : 'İşlem tamamlanamadı.',
            (payload.errors as Record<string, string[]> | undefined) ?? {},
        );
    }

    return payload as T;
}
