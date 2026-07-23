/**
 * Borçlar/Cari ekranlarının ortak tipleri + yardımcıları.
 */
import { api } from '@/lib/http';

export interface ReceivableRow {
    id: number;
    branch_id: number | null;
    name: string;
    phone: string | null;
    email: string | null;
    note: string | null;
    balance_minor: number;
    balance_display: string;
    is_active: boolean;
    open_debt_orders_count: number;
    created_at: string | null;
}

export interface ReceivableTransactionRow {
    id: number;
    type: 'debt_transfer' | 'payment' | 'adjustment';
    amount_minor: number;
    method: string | null;
    note: string | null;
    balance_after_minor: number;
    order_id: number | null;
    performed_by: string | null;
    created_at: string | null;
}

export interface ReceivableDebtOrderRow {
    id: number;
    table_name: string | null;
    total_minor: number;
    debt_amount_minor: number | null;
    closed_at: string | null;
}

export interface Paginated<T> {
    data: T[];
    current_page: number;
    last_page: number;
    total: number;
}

/** Kuruş → "1.234,56" (₺ işareti görüntüde). */
export function money(minor: number): string {
    return (minor / 100).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Detay sayfasındaki "Borca taşı" modalı için hafif liste (tam CRUD gerekmez). */
export async function fetchActiveReceivables(): Promise<ReceivableRow[]> {
    const res = await api<{ receivables: Paginated<ReceivableRow> }>('/api/v1/receivables?per_page=200');
    return res.receivables.data;
}
