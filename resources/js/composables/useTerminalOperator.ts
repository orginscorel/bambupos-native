import { computed } from 'vue';
import { router, usePage } from '@inertiajs/vue3';
import { api } from '@/lib/http';

/**
 * §13 Faz C — Terminal AKTİF OPERATÖRÜ (istemci tarafı).
 *
 * Paylaşımlı kasa / sipariş-giriş cihazında "kim çalışıyor"u yönetir. Aktif
 * operatör sunucu OTURUMUNDA tutulur; burada yalnız okunur/değiştirilir. Geçerli
 * operatör Inertia `auth.terminal_operator` prop'undan REAKTİF gelir (sunucu tek
 * doğruluk kaynağı) — set/clear sonrası `only:['auth']` ile tazelenir, böylece
 * üst bardaki çip anında güncellenir. NORMAL (terminal olmayan) oturumda kavram
 * yoktur (isTerminal=false).
 */

export interface TerminalOperatorInfo {
    id: number;
    name: string;
}

export interface TerminalStaffOption {
    id: number;
    name: string;
    position: string | null;
}

export interface TerminalOperatorStats {
    operator: TerminalOperatorInfo | null;
    shift_start: string | null;
    on_shift: boolean;
    break_count: number;
    break_minutes: number;
    orders_opened: number;
    items_added: number;
    items_cancelled: number;
    server_time: string;
}

interface TerminalAuthProps {
    is_terminal?: boolean;
    terminal_operator?: TerminalOperatorInfo | null;
}

export function useTerminalOperator() {
    const page = usePage();

    const auth = computed<TerminalAuthProps | null>(
        () => (page.props.auth as TerminalAuthProps | null) ?? null,
    );

    const isTerminal = computed<boolean>(() => Boolean(auth.value?.is_terminal));

    /** Geçerli aktif operatör (yoksa null → "Personel Seç"). */
    const current = computed<TerminalOperatorInfo | null>(
        () => auth.value?.terminal_operator ?? null,
    );

    /** Bu terminalin şubesindeki seçilebilir personel (aktif, gizli-olmayan). */
    async function loadOperators(): Promise<TerminalStaffOption[]> {
        const res = await api<{ operators: TerminalStaffOption[] }>('/terminal/operators');
        return res.operators;
    }

    /** Personeli PIN'le aktif operatör yap; başarıda auth prop'u tazele. */
    async function setOperator(staffId: number, pin: string): Promise<TerminalOperatorInfo> {
        const res = await api<{ operator: TerminalOperatorInfo }>('/terminal/operator', {
            method: 'POST',
            body: { staff_id: staffId, pin },
        });
        await refreshAuth();
        return res.operator;
    }

    /** Aktif operatörü temizle (personel değişimi); auth prop'u tazele. */
    async function clearOperator(): Promise<void> {
        await api('/terminal/operator/clear', { method: 'POST' });
        await refreshAuth();
    }

    function refreshAuth(): Promise<void> {
        return new Promise<void>((resolve) => {
            router.reload({ only: ['auth'], onFinish: () => resolve() });
        });
    }

    /** Aktif operatörün bugünkü özeti (personel barı). */
    async function loadStats(): Promise<TerminalOperatorStats> {
        return api<TerminalOperatorStats>('/terminal/operator/stats');
    }

    return { isTerminal, current, loadOperators, setOperator, clearOperator, loadStats };
}
