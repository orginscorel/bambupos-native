/** Personel Portalı — /api/v1/portal uçlarının yanıt şekilleri. */

export interface PortalBreak {
    kind: string;
    kind_label: string;
    started_at: string;
    ended_at: string | null;
}

export interface PortalEntry {
    id: number;
    clock_in_at: string;
    worked_min: number;
    break_total_min: number;
    toilet_total_min: number;
    breaks: PortalBreak[];
}

export interface PortalShift {
    starts_at: string;
    ends_at: string;
    position: string | null;
}

export interface PortalState {
    status: 'off' | 'working';
    on_break: boolean;
    break_kind: string | null;
    break_started_at: string | null;
    entry: PortalEntry | null;
    today_shift: PortalShift | null;
    server_now: string;
}

export interface PortalReportBucket {
    worked_min: number;
    break_min: number;
    toilet_min: number;
    entries: number;
}

export interface PortalReportRow {
    id: number;
    date: string;
    clock_in_at: string;
    clock_out_at: string | null;
    status: string;
    worked_min: number;
    break_min: number;
    toilet_min: number;
}

export interface PortalReports {
    today: PortalReportBucket;
    month: PortalReportBucket;
    history: PortalReportRow[];
}

/** Dakikayı "2s 15dk" biçiminde gösterir. */
export function formatMinutes(min: number): string {
    const m = Math.max(0, Math.round(min));
    const h = Math.floor(m / 60);
    const rem = m % 60;
    if (h > 0 && rem > 0) return `${h}s ${rem}dk`;
    if (h > 0) return `${h}s`;
    return `${rem}dk`;
}
