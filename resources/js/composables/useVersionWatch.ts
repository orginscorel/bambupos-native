/**
 * Sürüm güncelleme gözcüsü — chat/dcim'deki gibi "yeni güncelleme geldi" bildirimi.
 *
 * Sayfa yüklenince güncel sürümü (ilk fetch) referans "mevcut" say; sonra
 * periyodik olarak (varsayılan 3 dk, yalnız sekme görünürken) /api/v1/app-version
 * yoklar. Sürüm İLK görülenden farklıysa TEK SEFER kalıcı (duration 0) bir toast
 * gösterir; toast'a dokununca sayfa tam yenilenir.
 *
 * Ortak kabuklarda (panel / portal / patron / KDS) bir kez mount edilir.
 */
import { onBeforeUnmount, onMounted } from 'vue';
import { api } from '@/lib/http';
import { useToast } from '@/composables/useToast';

interface VersionResponse {
    version: string;
}

export function useVersionWatch(pollMs = 180000) {
    const toast = useToast();

    /** null → henüz ilk (referans) sürüm alınmadı. */
    let baseline: string | null = null;
    /** Toast bir kez gösterildikten sonra tekrar gösterme + yoklamayı durdur. */
    let notified = false;
    let timer: ReturnType<typeof setInterval> | null = null;

    async function check(): Promise<void> {
        if (notified) return;
        let res: VersionResponse;
        try {
            res = await api<VersionResponse>('/api/v1/app-version');
        } catch {
            // Sessiz — geçici ağ/oturum hatası bir sonraki yoklamada düzelir.
            return;
        }
        const current = res?.version;
        if (!current) return;

        if (baseline === null) {
            // İlk yükleme: mevcut sürümü referans al, bildirim YOK.
            baseline = current;
            return;
        }

        if (current !== baseline) {
            notified = true;
            if (timer) {
                clearInterval(timer);
                timer = null;
            }
            toast.toast({
                variant: 'info',
                icon: 'refresh-cw',
                title: 'Güncelleme mevcut',
                message: 'Yeni sürüm yayınlandı — yenilemek için dokunun',
                duration: 0, // kalıcı
                reload: true,
            });
        }
    }

    function onVisibility(): void {
        if (document.visibilityState === 'visible') void check();
    }

    onMounted(() => {
        void check();
        timer = setInterval(() => {
            if (document.visibilityState === 'visible') void check();
        }, pollMs);
        document.addEventListener('visibilitychange', onVisibility);
    });

    onBeforeUnmount(() => {
        if (timer) clearInterval(timer);
        document.removeEventListener('visibilitychange', onVisibility);
    });
}
