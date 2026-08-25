/**
 * Terminal kalp atışı — istasyon ekranı açık kaldığı sürece cihazın
 * `last_seen_at`'ini periyodik tazeler (POST /terminal/heartbeat) → yönetim
 * panelindeki "Çevrimiçi/Çevrimdışı" rozeti doğru kalır.
 *
 * Sorun: terminal token'ı yalnız ilk açılışta `last_seen_at` yazıyordu; KDS
 * polling'i ona dokunmadığı için 3 dk sonra cihaz aktifken bile "Çevrimdışı"
 * görünüyordu. Bu composable Kiosk'un heartbeat desenini terminale taşır.
 *
 * BUG #3 düzeltmesi: yanıt `{status:'locked'}` dönebilir (panelden "uzaktan
 * kilit" tetiklendi) — ESKİDEN bu yanıt hiç okunmuyordu, ekran bir sonraki
 * tam sayfa açılışına kadar (dakikalarca) açık kalabiliyordu. Şimdi 'locked'
 * görülür görülmez tam sayfa `/terminal/relock`'a yönlendirilir — bu uç
 * oturumu düşürür ve kendini-yokla `terminal.locked` ekranını üretir (aynı
 * `show()`'daki kilit dalı, token olmadan).
 *
 * Yalnız `is_terminal` oturumunda çalışır; başka kullanıcıda no-op.
 */
import { onBeforeUnmount, onMounted } from 'vue';
import { usePage } from '@inertiajs/vue3';
import { api } from '@/lib/http';

const INTERVAL_MS = 45000; // < ONLINE_WINDOW_SECONDS (180) → daima taze

export interface UseTerminalHeartbeatOptions {
    /** 'locked' yanıtında çağrılır; verilmezse varsayılan: /terminal/relock'a tam sayfa yönlendirme. */
    onLocked?: () => void;
}

export function useTerminalHeartbeat(options: UseTerminalHeartbeatOptions = {}): void {
    const page = usePage();
    const isTerminal = Boolean((page.props.auth as { is_terminal?: boolean } | null)?.is_terminal);
    if (!isTerminal) return;

    let timer: ReturnType<typeof setInterval> | null = null;
    let redirecting = false; // ANINDA kilit sonrası tekrar tekrar tetiklenmesin

    function handleLocked(): void {
        if (redirecting) return;
        redirecting = true;
        if (timer) clearInterval(timer);
        if (options.onLocked) {
            options.onLocked();
            return;
        }
        window.location.href = '/terminal/relock';
    }

    async function ping(): Promise<void> {
        if (redirecting) return;
        try {
            const res = await api<{ status?: string }>('/terminal/heartbeat', { method: 'POST' });
            if (res?.status === 'locked') handleLocked();
        } catch {
            /* geçici ağ hatası — bir sonraki atışta düzelir */
        }
    }

    function onVisible(): void {
        if (typeof document !== 'undefined' && !document.hidden) void ping();
    }

    onMounted(() => {
        void ping();
        timer = setInterval(() => void ping(), INTERVAL_MS);
        document.addEventListener('visibilitychange', onVisible);
    });

    onBeforeUnmount(() => {
        if (timer) clearInterval(timer);
        document.removeEventListener('visibilitychange', onVisible);
    });
}
