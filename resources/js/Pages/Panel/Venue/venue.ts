/**
 * Venue sayfalarının ortak tipleri + yardımcıları.
 * Enum sözlükleri (durum/tür/şekil) sunucudan Inertia prop'u olarak gelir
 * (PHP enum tek kaynak; TS tarafında kopya tutulmaz).
 */
import { api } from '@/lib/http';

export interface OptionMeta {
    value: string;
    label: string;
}

export interface StatusMeta extends OptionMeta {
    icon: string;
    variant: 'neutral' | 'primary' | 'success' | 'warning' | 'danger' | 'info';
}

export interface VenueMeta {
    statuses: StatusMeta[];
    areaTypes: OptionMeta[];
    shapes: OptionMeta[];
}

export interface BranchRow {
    id: number;
    name: string;
    code: string | null;
    address: string | null;
    phone: string | null;
    timezone: string;
    is_active: boolean;
    showcase: Record<string, unknown> | null;
    has_qr_token: boolean;
    areas_count: number;
    tables_count: number;
}

export interface FloorRow {
    id: number;
    branch_id: number;
    name: string;
    sort_order: number;
    areas_count: number;
}

export interface AreaRow {
    id: number;
    branch_id: number;
    floor_id: number | null;
    floor_name: string | null;
    name: string;
    type: string;
    type_label: string;
    sort_order: number;
    is_active: boolean;
    tables_count: number;
}

export interface TableRow {
    id: number;
    branch_id: number;
    branch_name: string | null;
    area_id: number | null;
    area_name: string | null;
    floor_name: string | null;
    name: string;
    number: number | null;
    capacity: number;
    shape: string;
    shape_label: string;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    is_joinable: boolean;
    notes: string | null;
    is_active: boolean;
    menu_url: string;
    qr_rotated_at: string | null;
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
}

export function metaFromProps(props: Record<string, unknown>): VenueMeta {
    return {
        statuses: (props.statuses as StatusMeta[]) ?? [],
        areaTypes: (props.areaTypes as OptionMeta[]) ?? [],
        shapes: (props.shapes as OptionMeta[]) ?? [],
    };
}

export async function fetchBranches(): Promise<BranchRow[]> {
    const res = await api<{ branches: BranchRow[] }>('/api/v1/venue/branches');
    return res.branches;
}

export async function fetchFloors(branchId: number | null): Promise<FloorRow[]> {
    const q = branchId ? `?branch_id=${branchId}` : '';
    const res = await api<{ floors: FloorRow[] }>(`/api/v1/venue/floors${q}`);
    return res.floors;
}

export async function fetchAreas(branchId: number | null): Promise<AreaRow[]> {
    const q = branchId ? `?branch_id=${branchId}` : '';
    const res = await api<{ areas: AreaRow[] }>(`/api/v1/venue/areas${q}`);
    return res.areas;
}

function xsrfToken(): string {
    const match = document.cookie.match(/(?:^|;\s*)XSRF-TOKEN=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : '';
}

/** Multipart yükleme (api() JSON gönderir; logo için FormData gerekir). */
export async function uploadFile<T>(path: string, field: string, file: File): Promise<T> {
    const body = new FormData();
    body.append(field, file);

    const response = await fetch(path, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-XSRF-TOKEN': xsrfToken(),
        },
        body,
    });

    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;

    if (!response.ok) {
        const errors = (payload.errors as Record<string, string[]>) ?? {};
        const first = Object.values(errors)[0]?.[0];
        throw new Error(first || (payload.message as string) || 'Yükleme başarısız.');
    }

    return payload as T;
}
