import { computed, ref } from 'vue';
import { usePage } from '@inertiajs/vue3';

/**
 * §13 Faz B — Terminal PIN kapısı (istemci tarafı).
 *
 * Kasa / sipariş-giriş terminali cihaza-kilitli GİZLİ bir kullanıcıyla çalışır.
 * Hassas para eylemleri (ödeme al, adisyon iptali, iade, ikram) yapılırken
 * personel PIN'i istenir; PIN gövdeye eklenir, backend personeli çözer + eyleme
 * atfeder (TerminalPinGate). NORMAL (terminal olmayan) oturumda PIN İSTENMEZ —
 * mevcut davranış korunur.
 *
 * Tek PIN modalı bir sayfada yeterli olduğundan durum modül düzeyinde tekildir;
 * StaffPinDialog.vue bu duruma bağlanır, sayfalar `collectPin()` çağırır.
 */

const open = ref(false);
const pin = ref('');
const staffCode = ref('');
const showStaffCode = ref(false);
let resolver: ((v: { pin: string; staff_code: string | null } | null) => void) | null = null;

/** StaffPinDialog.vue bileşeninin bağlandığı paylaşılan durum + eylemler. */
export function useTerminalPinDialog() {
    function submit(): void {
        if (!pin.value) return;
        const r = resolver;
        resolver = null;
        open.value = false;
        r?.({ pin: pin.value, staff_code: staffCode.value.trim() || null });
    }

    function cancel(): void {
        const r = resolver;
        resolver = null;
        open.value = false;
        r?.(null);
    }

    return { open, pin, staffCode, showStaffCode, submit, cancel };
}

/** Sayfaların kullandığı kapı: is_terminal bayrağı + hassas eylem PIN toplama. */
export function useTerminalPin() {
    const page = usePage();

    const isTerminal = computed(() =>
        Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal),
    );

    const stationLabel = computed(() => {
        const key = (page.props.auth as { terminal_station?: string | null } | null)?.terminal_station ?? '';
        const map: Record<string, string> = {
            kasa: 'Kasa',
            order_entry: 'Sipariş Girişi',
            kitchen: 'Mutfak',
            barista: 'Barista',
            komi: 'Komi',
        };
        return map[key] ?? key;
    });

    function promptPin(): Promise<{ pin: string; staff_code: string | null } | null> {
        // Zaten bekleyen bir PIN isteği varsa onu İPTAL et (null ile çöz) — aksi
        // halde eski resolver yetim kalır ve o eylem sonsuza dek askıda kalır.
        if (resolver) {
            const prev = resolver;
            resolver = null;
            prev(null);
        }
        pin.value = '';
        staffCode.value = '';
        showStaffCode.value = false;
        open.value = true;
        return new Promise((resolve) => {
            resolver = resolve;
        });
    }

    /** Terminalde aktif operatör (PIN'le giriş yapmış personel) var mı? */
    const hasActiveOperator = computed(() =>
        Boolean((page.props.auth as { terminal_operator?: { id: number } | null } | null)?.terminal_operator),
    );

    /**
     * Hassas eyleme eklenecek gövde alanlarını döndürür.
     *  - Normal oturum → `{}` (PIN yok, mevcut davranış).
     *  - Terminal + AKTİF OPERATÖR → `{}` (yeniden PIN SORMA; backend eylemi aktif
     *    operatöre atfeder — operatör zaten PIN'le giriş yaptı, kimliği bellidir).
     *  - Terminal + operatör YOK → PIN modalı; onaylanırsa `{ pin, staff_code }`,
     *    iptal edilirse `null` (çağıran eylemi İPTAL etmeli).
     */
    async function collectPin(): Promise<Record<string, unknown> | null> {
        if (!isTerminal.value) return {};
        if (hasActiveOperator.value) return {}; // operatör belli → PIN'siz atıf
        const res = await promptPin();
        if (!res) return null;
        return { pin: res.pin, staff_code: res.staff_code };
    }

    return { isTerminal, stationLabel, collectPin };
}
