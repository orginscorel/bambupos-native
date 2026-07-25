/** Shifts modülü tip tanımları (API sözleşmesi). */

export interface StaffLite {
    id: number;
    name: string;
    position: string | null;
    branch_id?: number | null;
    staff_code?: string | null;
}

export interface BranchLite {
    id: number;
    name: string;
}

export interface ShiftsMeta {
    staff: StaffLite[];
    branches: BranchLite[];
    positions: string[];
    default_break_min: number;
    can: { view_all: boolean; manage: boolean };
}

export interface ShiftRow {
    id: number;
    branch_id: number;
    user_id: number;
    user?: StaffLite | null;
    position: string | null;
    starts_at: string;
    ends_at: string;
    break_min: number;
    note: string | null;
    repeat_group: string | null;
}

export interface LeaveRow {
    id: number;
    user_id: number;
    user?: StaffLite | null;
    type: string;
    starts_on: string;
    ends_on: string;
    reason: string | null;
    status: string;
    decision_note?: string | null;
    decided_by?: { id: number; name: string } | null;
    created_by?: { id: number; name: string } | null;
}

export interface StaffingWarning {
    date: string;
    branch_id: number;
    position: string | null;
    required: number;
    planned: number;
}

export interface ScheduleData {
    shifts: ShiftRow[];
    leaves: LeaveRow[];
    warnings: StaffingWarning[];
}

export interface BreakRow {
    started_at: string;
    ended_at: string | null;
}

export interface TimeEntryRow {
    id: number;
    user: StaffLite | null;
    branch: BranchLite | null;
    shift: { id: number; starts_at: string; ends_at: string } | null;
    clock_in_at: string;
    clock_out_at: string | null;
    method_in: string;
    method_out: string | null;
    device: { id: number; name: string } | null;
    ip_in: string | null;
    ip_out: string | null;
    break_total_min: number;
    worked_min: number | null;
    planned_min: number | null;
    overtime_min: number;
    missing_min: number;
    late_min: number;
    early_leave_min: number;
    status: string;
    approved_at: string | null;
    edited_at: string | null;
    edit_reason: string | null;
}

export interface SwapRow {
    id: number;
    status: string;
    reason: string | null;
    decision_note: string | null;
    shift: (ShiftRow & { user?: StaffLite | null; branch?: BranchLite | null }) | null;
    requested_by: StaffLite | null;
    target_user: StaffLite | null;
    decided_by: StaffLite | null;
    created_at?: string;
}

export interface AttendanceRow {
    user: StaffLite;
    days_worked: number;
    worked_min: number;
    break_min: number;
    overtime_min: number;
    missing_min: number;
    late_count: number;
    late_min: number;
    early_leave_count: number;
    planned_shifts: number;
    leave_days: Record<string, number>;
    auto_absent_days: number;
}

export interface PerformanceRow {
    user: StaffLite;
    order_count: number;
    sales_minor: number;
    avg_service_min: number | null;
    cancelled_count: number;
    cancel_rate: number;
    discount_rate: number;
    comp_rate: number;
    discount_minor: number;
    comp_minor: number;
    table_turnover_min: number | null;
}

export interface ClockState {
    status: 'off' | 'working' | 'closed';
    on_break: boolean;
}

export interface ClockResponse {
    user: StaffLite;
    state: ClockState;
    entry: {
        id: number;
        clock_in_at: string;
        clock_out_at: string | null;
        status: string;
        break_total_min: number;
        worked_min: number | null;
        overtime_min: number;
        late_min: number;
        early_leave_min: number;
        breaks: BreakRow[];
    } | null;
}

export interface ShiftSettings {
    standard_daily_min?: number;
    late_tolerance_min?: number;
    early_leave_tolerance_min?: number;
    default_break_min?: number;
    location_tracking_enabled: boolean;
    location_policy: string | null;
}

export interface ClockDeviceRow {
    id: number;
    branch_id: number | null;
    branch?: BranchLite | null;
    name: string;
    is_active: boolean;
    last_seen_at: string | null;
}

export interface StaffingRuleRow {
    id: number;
    branch_id: number;
    branch?: BranchLite | null;
    weekday: number | null;
    position: string | null;
    min_count: number;
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
}

export const LEAVE_TYPE_LABELS: Record<string, string> = {
    annual: 'Yıllık izin',
    sick: 'Rapor',
    unpaid: 'Ücretsiz izin',
    holiday: 'Resmî tatil',
    absence: 'Devamsızlık',
    other: 'Diğer',
};

export const STATUS_LABELS: Record<string, string> = {
    pending: 'Bekliyor',
    approved: 'Onaylandı',
    rejected: 'Reddedildi',
    cancelled: 'İptal',
};

export const WEEKDAY_LABELS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
