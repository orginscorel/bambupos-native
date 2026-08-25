/**
 * Sipariş (garson) ekranlarının ortak tipleri + yardımcıları.
 * Enum sözlükleri (durum/kanal) sunucudan Inertia prop'u olarak gelir
 * (PHP enum tek kaynak; TS tarafında kopya tutulmaz).
 */
import { api, ApiError } from '@/lib/http';

export interface StatusMeta {
    value: string;
    label: string;
    icon: string;
    variant: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
}

export interface OrdersMeta {
    orderStatuses: StatusMeta[];
    itemStatuses: StatusMeta[];
    channels: StatusMeta[];
    tableStatuses: StatusMeta[];
    discountApprovalPercent: number;
}

export function metaFromProps(props: Record<string, unknown>): OrdersMeta {
    return {
        orderStatuses: (props.orderStatuses as StatusMeta[]) ?? [],
        itemStatuses: (props.itemStatuses as StatusMeta[]) ?? [],
        channels: (props.channels as StatusMeta[]) ?? [],
        tableStatuses: (props.tableStatuses as StatusMeta[]) ?? [],
        discountApprovalPercent: (props.discountApprovalPercent as number) ?? 10,
    };
}

export interface OrderItemOptionRow {
    id: number;
    group_name: string;
    option_name: string;
    price_minor: number;
}

export interface OrderItemRow {
    id: number;
    product_id: number | null;
    variant_id: number | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    is_active: boolean;
    qty: number;
    name: string;
    variant_name: string | null;
    unit_price_minor: number;
    options_price_minor: number;
    tax_rate: number;
    station: string | null;
    discount_minor: number;
    is_comp: boolean;
    comp_reason: string | null;
    line_total_minor: number;
    line_total_display: string;
    note: string | null;
    cancel_reason: string | null;
    options: OrderItemOptionRow[];
}

export interface OrderEventRow {
    id: number;
    type: string;
    from_status: string | null;
    to_status: string | null;
    user: string | null;
    payload: Record<string, unknown> | null;
    created_at: string | null;
}

export interface OrderSummary {
    id: number;
    branch_id: number;
    table_id: number | null;
    table_name: string | null;
    channel: string;
    channel_label: string;
    channel_icon: string;
    channel_variant: StatusMeta['variant'];
    source_label: string;
    source_icon: string;
    source_variant: StatusMeta['variant'];
    service_type: string;
    service_type_label: string;
    service_type_icon: string;
    service_type_variant: StatusMeta['variant'];
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    is_open: boolean;
    version: number;
    guest_count: number | null;
    note: string | null;
    customer_name: string | null;
    customer_phone: string | null;
    items_count: number;
    served_count: number;
    items_total_minor: number;
    discount_minor: number;
    discount_percent: number | null;
    discount_reason: string | null;
    comp_total_minor: number;
    vat_total_minor: number;
    total_minor: number;
    paid_minor: number;
    paid_display: string;
    payment_state: 'paid' | 'partial' | 'unpaid';
    payment_label: string;
    refunded_minor: number;
    remaining_minor: number;
    total_display: string;
    remaining_display: string;
    /** Bu adisyona bağlı ek masaların adları (birleşik masalar). */
    linked_table_names?: string[];
    opened_by: string | null;
    placed_at: string | null;
    created_at: string | null;
    closed_at: string | null;
}

export interface OrderDetail extends OrderSummary {
    items: OrderItemRow[];
    events: OrderEventRow[];
}

export interface BoardTable {
    id: number;
    name: string;
    number: number | null;
    capacity: number;
    area_name: string | null;
    floor_name: string | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    /** Bugünkü aktif rezervasyon (henüz oturtulmadı) — boş masada "Rezerve" göstergesi. */
    reservation: { name: string; time: string; time_end: string; party: number } | null;
    /** Bu masa başka bir adisyona bağlıysa (grup birleştirmesi) ana adisyon. */
    linked_to?: { order_id: number; table_name: string | null; remaining_minor: number; items_count: number } | null;
    orders: OrderSummary[];
}

export interface ServiceRequestRow {
    id: number;
    kind: string;
    kind_label: string;
    kind_icon: string;
    table_id: number;
    table_name: string | null;
    created_at: string | null;
}

export interface BoardData {
    tables: BoardTable[];
    channel_orders: OrderSummary[];
    pending_approval: OrderSummary[];
    service_requests: ServiceRequestRow[];
}

/* ---- Hızlı ekleme kataloğu ---- */

export interface CatalogVariant {
    id: number;
    name: string;
    price_minor: number;
    is_default: boolean;
}

export interface CatalogOption {
    id: number;
    name: string;
    price_minor: number;
    is_default: boolean;
}

export interface CatalogOptionGroup {
    id: number;
    name: string;
    selection_type: 'single' | 'multiple';
    is_required: boolean;
    min_select: number;
    max_select: number | null;
    free_limit: number;
    options: CatalogOption[];
}

/**
 * Grup içi seçenek toplamı (sunucudaki resolveOptions ile AYNI kural):
 * seçilenler fiyata göre büyükten küçüğe sıralanır, ilk `free_limit`
 * tanesi ücretsizdir; kalanlar kendi fiyatından ücretlendirilir.
 */
export function groupOptionsPrice(group: CatalogOptionGroup, selectedIds: Set<number>): number {
    const selected = group.options
        .filter((o) => selectedIds.has(o.id))
        .sort((a, b) => b.price_minor - a.price_minor);

    return selected.slice(Math.max(0, group.free_limit)).reduce((n, o) => n + o.price_minor, 0);
}

export interface CatalogProduct {
    id: number;
    category_id: number | null;
    name: string;
    price_minor: number;
    discounted_price_minor: number | null;
    kiosk_price_minor: number | null;
    package_price_minor: number | null;
    qr_price_minor: number | null;
    is_available: boolean;
    /** Hızlı ekleme ızgarası thumbnail'ı (birincil ürün görseli); yoksa null. */
    image_url: string | null;
    channels: string[] | null;
    min_order_qty: number;
    max_order_qty: number | null;
    station: string | null;
    variants: CatalogVariant[];
    option_groups: CatalogOptionGroup[];
}

export interface CatalogCategory {
    id: number;
    /** Üst kategori (yoksa null) — iki seviyeli kategori gezinmesi için. */
    parent_id?: number | null;
    name: string;
    icon: string | null;
    color: string | null;
}

export interface OrderCatalog {
    categories: CatalogCategory[];
    products: CatalogProduct[];
}

export interface BranchRow {
    id: number;
    name: string;
}

/* ---- API yardımcıları ---- */

export async function fetchBoard(branchId: number | null): Promise<BoardData> {
    const q = branchId ? `?branch_id=${branchId}` : '';
    return api<BoardData>(`/api/v1/orders/board${q}`);
}

export async function fetchOrder(id: number): Promise<OrderDetail> {
    const res = await api<{ order: OrderDetail }>(`/api/v1/orders/${id}`);
    return res.order;
}

export async function fetchOrderCatalog(branchId: number | null): Promise<OrderCatalog> {
    const q = branchId ? `?branch_id=${branchId}` : '';
    return api<OrderCatalog>(`/api/v1/orders/catalog${q}`);
}

export async function fetchBranches(): Promise<BranchRow[]> {
    const res = await api<{ branches: BranchRow[] }>('/api/v1/venue/branches');
    return res.branches;
}

/** Kuruş → "1.234,56" (₺ işareti görüntüde). */
export function money(minor: number): string {
    return (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Ürünün kanaldaki birim fiyatı (sunucudaki channelUnitPrice ile aynı öncelik). */
export function channelPrice(p: CatalogProduct, channel: string): number {
    const col =
        channel === 'kiosk' ? p.kiosk_price_minor
        : channel === 'package' || channel === 'pickup' ? p.package_price_minor
        : channel === 'qr' ? p.qr_price_minor
        : null;

    return col ?? p.discounted_price_minor ?? p.price_minor;
}

/**
 * Idempotency-Key başlıklı POST (lib/http api() özel başlık desteklemez;
 * paylaşımlı dosyaya dokunmamak için yerel eşdeğeri).
 */
export async function apiIdempotent<T = unknown>(path: string, body: unknown, idempotencyKey: string): Promise<T> {
    const xsrf = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);

    const response = await fetch(path, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-XSRF-TOKEN': xsrf ? decodeURIComponent(xsrf[1]) : '',
            'Idempotency-Key': idempotencyKey,
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

/** Idempotency-Key üretimi (çift dokunma sipariş çoğaltmasın). */
export function newIdempotencyKey(): string {
    if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
    return `idk-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

/** Geçen süre: "12 dk", "1 sa 05 dk". */
export function elapsed(iso: string | null): string {
    if (!iso) return '';
    const mins = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
    if (mins < 60) return `${mins} dk`;
    return `${Math.floor(mins / 60)} sa ${String(mins % 60).padStart(2, '0')} dk`;
}

/**
 * Siparişin "verildi" anından geçen süre — KDS ile AYNI kaynak (placed_at,
 * onay bekliyorsa created_at'e düşer; sunucu OrderPresenter/KdsPresenter
 * ile birebir aynı kural). Siparişler panosu bunun yerine yalnız
 * created_at (adisyonun AÇILDIĞI an) kullanırsa mutfakla tutarsız süre
 * gösterir — bug buydu.
 */
export function orderElapsed(o: Pick<OrderSummary, 'placed_at' | 'created_at'>): string {
    return elapsed(o.placed_at ?? o.created_at);
}
