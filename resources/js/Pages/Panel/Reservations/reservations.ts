/**
 * Rezervasyon sayfalarının ortak tipleri + yardımcıları.
 * Enum sözlükleri (durum/kaynak/kapora) sunucudan Inertia prop'u gelir
 * (PHP enum tek kaynak; TS tarafında kopya tutulmaz — Venue deseni).
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

export interface ReservationsMeta {
    statuses: StatusMeta[];
    sources: OptionMeta[];
    depositStatuses: (OptionMeta & { variant: string })[];
    waitlistStatuses: StatusMeta[];
    defaults: {
        duration_minutes: number;
        buffer_minutes: number;
        max_party_size: number;
    };
}

export function metaFromProps(props: Record<string, unknown>): ReservationsMeta {
    return {
        statuses: (props.statuses as StatusMeta[]) ?? [],
        sources: (props.sources as OptionMeta[]) ?? [],
        depositStatuses: (props.depositStatuses as (OptionMeta & { variant: string })[]) ?? [],
        waitlistStatuses: (props.waitlistStatuses as StatusMeta[]) ?? [],
        defaults: (props.defaults as ReservationsMeta['defaults']) ?? {
            duration_minutes: 120,
            buffer_minutes: 15,
            max_party_size: 40,
        },
    };
}

export interface ReservationTableRef {
    id: number;
    name: string;
    number: number | null;
    capacity: number;
}

export interface ReservationRow {
    id: number;
    branch_id: number;
    customer_name: string;
    customer_phone: string | null;
    customer_email: string | null;
    reserved_at: string;
    reserved_date: string;
    reserved_time: string;
    ends_at: string;
    blocks_until: string;
    duration_minutes: number;
    buffer_minutes: number;
    party_size: number;
    area_id: number | null;
    area_name: string | null;
    special_note: string | null;
    has_allergy_note: boolean;
    allergy_note: string | null; // yalnız reservations.view_sensitive iznine sunulur
    occasion: string | null;
    occasion_note: string | null;
    deposit_minor: number;
    deposit_status: string;
    deposit_status_label: string;
    deposit_status_variant: string;
    source: string;
    source_label: string;
    created_by_name: string | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    allowed_transitions: string[];
    cancel_reason: string | null;
    reminder_status: string;
    reminder_sent_at: string | null;
    tables: ReservationTableRef[];
    created_at: string | null;
}

export interface WaitlistRow {
    id: number;
    branch_id: number;
    customer_name: string;
    customer_phone: string | null;
    party_size: number;
    note: string | null;
    status: string;
    status_label: string;
    status_icon: string;
    status_variant: StatusMeta['variant'];
    position: number | null;
    quoted_wait_minutes: number | null;
    estimated_wait_minutes: number | null;
    waiting_since: string | null;
    notified_at: string | null;
}

export interface AvailabilityTable {
    id: number;
    name: string;
    number: number | null;
    capacity: number;
    is_joinable: boolean;
    area_id: number | null;
    area_name: string | null;
    status: string;
    available: boolean;
}

export interface NoShowReport {
    from: string;
    to: string;
    total: number;
    no_shows: number;
    completed: number;
    cancelled: number;
    no_show_rate: number;
    forfeited_deposit_minor: number;
    repeat_offenders: { customer_phone: string; customer_name: string; no_show_count: number }[];
    rows: ReservationRow[];
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
}

/** Kuruş → "₺ 1.234,56" */
export function formatMinor(minor: number): string {
    return '₺ ' + (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

export async function fetchReservations(params: URLSearchParams): Promise<Paginated<ReservationRow>> {
    const res = await api<{ reservations: Paginated<ReservationRow> }>(`/api/v1/reservations?${params}`);
    return res.reservations;
}

export async function fetchAvailability(body: {
    branch_id: number;
    reserved_at: string;
    duration_minutes: number;
    buffer_minutes: number;
    ignore_reservation_id?: number;
}): Promise<AvailabilityTable[]> {
    const q = new URLSearchParams();
    q.set('branch_id', String(body.branch_id));
    q.set('reserved_at', body.reserved_at);
    q.set('duration_minutes', String(body.duration_minutes));
    q.set('buffer_minutes', String(body.buffer_minutes));
    if (body.ignore_reservation_id) q.set('ignore_reservation_id', String(body.ignore_reservation_id));

    const res = await api<{ tables: AvailabilityTable[] }>(`/api/v1/reservations/availability?${q}`);
    return res.tables;
}

/** ISO gün ("YYYY-MM-DD") üretimi — yerel saat diliminde. */
export function isoDate(d: Date): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

export function addDays(d: Date, days: number): Date {
    const copy = new Date(d);
    copy.setDate(copy.getDate() + days);
    return copy;
}

/** Haftanın pazartesi başlangıcı. */
export function startOfWeek(d: Date): Date {
    const copy = new Date(d);
    const day = (copy.getDay() + 6) % 7; // Pzt=0
    copy.setDate(copy.getDate() - day);
    return copy;
}

export function formatDayLabel(dateStr: string): string {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString('tr-TR', { weekday: 'long', day: 'numeric', month: 'long' });
}

export function formatShortDay(dateStr: string): string {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString('tr-TR', { weekday: 'short', day: 'numeric', month: 'short' });
}
