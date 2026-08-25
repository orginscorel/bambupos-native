/** Katalog domaini istemci tipleri (API şemasının aynası). */

export interface CategoryRow {
    id: number;
    parent_id: number | null;
    name: string;
    slug: string;
    description: string | null;
    icon: string | null;
    color: string | null;
    available_from: string | null;
    available_until: string | null;
    sort_order: number;
    is_active: boolean;
    products_count?: number;
}

export interface VariantRow {
    id?: number;
    name: string;
    price_minor: number;
    is_default: boolean;
    is_active: boolean;
}

export interface OptionRow {
    id?: number;
    option_group_id?: number;
    name: string;
    price_minor: number;
    is_default?: boolean;
    is_active?: boolean;
}

export interface OptionGroupRow {
    id: number;
    name: string;
    description: string | null;
    selection_type: 'single' | 'multiple';
    is_required: boolean;
    min_select: number;
    max_select: number | null;
    free_limit: number;
    is_active: boolean;
    options: OptionRow[];
    products_count?: number;
}

export interface AllergenRow {
    id: number;
    kind: 'allergen' | 'diet';
    code: string;
    name: string;
    description: string | null;
    icon: string | null;
    color: string | null;
    is_global?: boolean;
    products_count?: number;
}

export interface ProductImageRow {
    id: number;
    path: string;
    url: string;
    is_primary: boolean;
    original_name: string | null;
}

export interface ProductRow {
    id: number;
    name: string;
    description: string | null;
    sku: string | null;
    barcode: string | null;
    category_id: number | null;
    category?: { id: number; name: string } | null;
    price_minor: number;
    cost_minor: number | null;
    package_price_minor: number | null;
    kiosk_price_minor: number | null;
    qr_price_minor: number | null;
    discounted_price_minor: number | null;
    tax_rate: string | number;
    portion: string | null;
    unit: string | null;
    prep_minutes: number | null;
    weight_grams: number | null;
    calories: number | null;
    protein: string | number | null;
    carbs: string | number | null;
    fat: string | number | null;
    spiciness: number;
    is_new: boolean;
    is_chef_pick: boolean;
    is_bestseller: boolean;
    is_active: boolean;
    is_available: boolean;
    channels: string[] | null;
    available_from: string | null;
    available_until: string | null;
    station: string | null;
    track_stock: boolean;
    stock_quantity: number | null;
    min_order_qty: number;
    max_order_qty: number | null;
    sort_order: number;
    variants?: VariantRow[];
    option_groups?: OptionGroupRow[];
    allergens?: AllergenRow[];
    images?: ProductImageRow[];
    variants_count?: number;
}

export interface MenuRow {
    id: number;
    name: string;
    description: string | null;
    days: number[] | null;
    start_time: string | null;
    end_time: string | null;
    channels: string[] | null;
    is_active: boolean;
    categories: { id: number; name: string }[];
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
    per_page: number;
}

export const CHANNEL_LABELS: Record<string, string> = {
    qr: 'QR Menü',
    kiosk: 'Kiosk',
    package: 'Paket Servis',
    pos: 'Kasa / POS',
};

export const DAY_LABELS: Record<number, string> = {
    1: 'Pzt',
    2: 'Sal',
    3: 'Çar',
    4: 'Per',
    5: 'Cum',
    6: 'Cmt',
    7: 'Paz',
};

export const STATION_OPTIONS = [
    { value: '', label: '— Seçilmedi —' },
    { value: 'kitchen', label: 'Mutfak' },
    { value: 'grill', label: 'Izgara' },
    { value: 'bar', label: 'Bar / İçecek' },
    { value: 'dessert', label: 'Tatlı İstasyonu' },
    { value: 'hookah', label: 'Nargile' },
];

export const STATION_LABELS: Record<string, string> = Object.fromEntries(
    STATION_OPTIONS.filter((o) => o.value).map((o) => [o.value, o.label]),
);

/** "HH:MM:SS" → "HH:MM" (API TIME alanları için). */
export const toHm = (v: string | null): string => (v ? v.slice(0, 5) : '');
