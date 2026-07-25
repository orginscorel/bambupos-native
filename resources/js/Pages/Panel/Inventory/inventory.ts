/**
 * Stok ekranlarının ortak tipleri + API yardımcıları (Faz 6, §17).
 * Enum sözlükleri sunucudan Inertia prop'u gelir (PHP tek kaynak).
 * Miktarlar sunucuda milli-int'tir; ekrana ondalık dize gelir/gider.
 */
import { api } from '@/lib/http';

export interface OptionMeta {
    value: string;
    label: string;
    variant?: string;
    direction?: number;
    manual?: boolean;
}

export interface InventoryMeta {
    movementTypes: OptionMeta[];
    warehouseTypes: OptionMeta[];
    purchaseStatuses: OptionMeta[];
    canAdjust: boolean;
}

export function metaFromProps(props: Record<string, unknown>): InventoryMeta {
    return {
        movementTypes: (props.movementTypes as OptionMeta[]) ?? [],
        warehouseTypes: (props.warehouseTypes as OptionMeta[]) ?? [],
        purchaseStatuses: (props.purchaseStatuses as OptionMeta[]) ?? [],
        canAdjust: Boolean(props.canAdjust),
    };
}

/* ---- Tipler ---- */

export interface WarehouseRow {
    id: number;
    name: string;
    code: string | null;
    type: string;
    type_label: string;
    branch_id: number | null;
    branch_name: string | null;
    is_default: boolean;
    is_active: boolean;
    item_count: number;
    total_qty: string;
}

export interface LevelRow {
    warehouse_id: number;
    qty_milli: number;
    qty: string;
}

export interface ItemRow {
    id: number;
    name: string;
    code: string | null;
    barcode: string | null;
    category_id: number | null;
    category_name: string | null;
    base_unit: string;
    sub_unit: string | null;
    sub_unit_factor: number | null;
    on_hand_milli: number;
    on_hand: string;
    min_qty: string;
    critical_qty: string;
    max_qty: string | null;
    avg_cost_minor: number;
    last_cost_minor: number | null;
    last_purchase_at: string | null;
    default_supplier_id: number | null;
    default_supplier_name: string | null;
    track_expiry: boolean;
    track_lot: boolean;
    shelf_location: string | null;
    tax_rate: number;
    is_semi_finished: boolean;
    is_active: boolean;
    status: 'ok' | 'low' | 'critical' | 'negative';
    levels: LevelRow[];
}

export interface MovementRow {
    id: number;
    type: string;
    type_label: string;
    type_variant: string;
    item_id: number;
    item_name: string | null;
    warehouse_name: string | null;
    qty_milli: number;
    qty: string;
    unit: string;
    unit_cost_minor: number | null;
    total_cost_minor: number | null;
    lot_no: string | null;
    expires_at: string | null;
    ref_type: string | null;
    ref_id: number | null;
    description: string | null;
    user_name: string | null;
    occurred_at: string | null;
}

export interface MovementRequestRow {
    id: number;
    item_name: string | null;
    warehouse_name: string | null;
    type: string;
    type_label: string;
    qty: string;
    unit: string | null;
    description: string | null;
    requested_by: string;
    created_at: string | null;
}

export interface RecipeLineRow {
    item_id: number;
    item_name?: string | null;
    base_unit?: string | null;
    sub_unit?: string | null;
    sub_unit_factor?: number | null;
    qty: string;
    unit_entry: 'base' | 'sub';
    waste_percent: number;
    warehouse_id: number | null;
    line_cost_minor?: number;
}

export interface RecipeData {
    id: number;
    product_id: number | null;
    variant_id: number | null;
    item_id: number | null;
    branch_id: number | null;
    version: number;
    yield_qty: string;
    waste_percent: number;
    note: string | null;
    is_active: boolean;
    lines: RecipeLineRow[];
}

export interface RecipeProduct {
    id: number;
    name: string;
    variants: { id: number; name: string }[];
    recipes: { id: number; variant_id: number | null; branch_id: number | null; version: number }[];
}

export interface CountLineRow {
    item_id: number;
    item_name: string | null;
    unit: string | null;
    counted_qty: string | null;
    expected_qty: string | null;
    diff_qty: string | null;
    diff_milli: number | null;
}

export interface CountData {
    id: number;
    warehouse_id?: number;
    warehouse_name: string | null;
    status: string;
    is_blind: boolean;
    note: string | null;
    line_count?: number;
    created_at?: string | null;
    submitted_at: string | null;
    approved_at: string | null;
    lines?: CountLineRow[];
}

export interface SupplierRow {
    id: number;
    name: string;
    contact_name: string | null;
    phone: string | null;
    email: string | null;
    tax_no: string | null;
    address: string | null;
    payment_term_days: number;
    note: string | null;
    is_active: boolean;
}

export interface PurchaseLineRow {
    id: number;
    item_id: number;
    item_name: string | null;
    unit: string | null;
    qty: string;
    qty_milli: number;
    received_qty: string;
    received_qty_milli: number;
    returned_qty: string;
    unit_price_minor: number;
    line_total_minor: number;
}

export interface PurchaseRow {
    id: number;
    supplier_id?: number;
    supplier_name: string | null;
    warehouse_id?: number | null;
    warehouse_name: string | null;
    status: string;
    status_label: string;
    status_variant: string;
    payment_status: string;
    invoice_no: string | null;
    invoice_total_minor: number | null;
    paid_minor: number;
    due_date: string | null;
    expected_at: string | null;
    note?: string | null;
    line_count: number;
    created_at: string | null;
    lines?: PurchaseLineRow[];
}

export interface SuggestionGroup {
    supplier: { id: number | null; name: string };
    items: {
        item_id: number;
        name: string;
        base_unit: string;
        on_hand_milli: number;
        min_qty_milli: number;
        suggested_qty_milli: number;
        last_cost_minor: number | null;
        estimated_total_minor: number | null;
    }[];
}

/* ---- Biçim yardımcıları ---- */

/** milli → "1,5" görüntüsü. */
export function qty(milli: number): string {
    const value = milli / 1000;
    return new Intl.NumberFormat('tr-TR', { maximumFractionDigits: 3 }).format(value);
}

export const money = (minor: number): string =>
    new Intl.NumberFormat('tr-TR', { style: 'currency', currency: 'TRY' }).format(minor / 100);

export const paymentStatusLabel = (s: string): string =>
    s === 'paid' ? 'Ödendi' : s === 'partial' ? 'Kısmi ödendi' : 'Ödenmedi';

export const paymentStatusVariant = (s: string): 'success' | 'warning' | 'danger' =>
    s === 'paid' ? 'success' : s === 'partial' ? 'warning' : 'danger';

export const itemStatusLabel = (s: ItemRow['status']): string =>
    s === 'negative' ? 'Eksi stok' : s === 'critical' ? 'Kritik' : s === 'low' ? 'Azalıyor' : 'Yeterli';

export const itemStatusVariant = (s: ItemRow['status']): 'danger' | 'warning' | 'success' =>
    s === 'negative' || s === 'critical' ? 'danger' : s === 'low' ? 'warning' : 'success';

/* ---- API sarmalayıcıları ---- */

export const fetchWarehouses = async (): Promise<WarehouseRow[]> =>
    (await api<{ warehouses: WarehouseRow[] }>('/api/v1/inventory/warehouses')).warehouses;

export const fetchItems = async (params = ''): Promise<ItemRow[]> =>
    (await api<{ items: ItemRow[] }>(`/api/v1/inventory/items${params}`)).items;

export const fetchCategories = async (): Promise<{ id: number; name: string }[]> =>
    (await api<{ categories: { id: number; name: string }[] }>('/api/v1/inventory/categories')).categories;

export const fetchSuppliers = async (): Promise<SupplierRow[]> =>
    (await api<{ suppliers: SupplierRow[] }>('/api/v1/inventory/suppliers')).suppliers;
