/**
 * §8 Panel-içi bildirim zili — okunmamış sayısı + liste + okundu işaretleme.
 * Hafif poll (varsayılan 20 sn). Sekme gizliyken yoklamaz (görünürlük).
 *
 * EKLER:
 *  - Ses uyarısı: refresh sonrası YENİ okunmamış KRİTİK bildirim geldiğinde
 *    (id bazlı fark; İLK yüklemede çalmaz) tek bip. Ses tercihi kapalıysa sessiz.
 *  - Sekme dikkat: sekme gizliyken okunmamış varsa document.title'a "(N) "
 *    ön-eki konur; sekme görünürleşince önceki başlık geri gelir.
 */
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { api } from '@/lib/http';
import { useNotificationSound } from '@/composables/useNotificationSound';
import { useToast, type ToastVariant } from '@/composables/useToast';

/** Bildirim tipi → toast tonu (baloncuk rengi/ikonu). */
const VARIANT_BY_TYPE: Record<string, ToastVariant> = {
    order_placed: 'info',
    service_call: 'warning',
    item_ready: 'success',
    delivery_sla_breach: 'danger',
    task_assigned: 'info',
    leave_requested: 'warning',
    leave_decided: 'info',
    shift_reminder: 'info',
    low_stock: 'warning',
    awaiting_payment: 'info',
    debt_transferred: 'warning',
    order_needs_approval: 'warning',
};

export interface NotificationItem {
    id: number;
    type: string;
    title: string;
    body: string | null;
    icon: string;
    url: string;
    read: boolean;
    created_at: string | null;
}

/**
 * Sesle uyarılacak KRİTİK bildirim tipleri (sipariş/servis/SLA/görev/izin/mesai).
 * Bunların dışındaki tipler sessizce listeye düşer.
 */
const CRITICAL_TYPES = new Set<string>([
    'order_placed',
    'service_call',
    'item_ready',
    'delivery_sla_breach',
    'task_assigned',
    'leave_requested',
    'leave_decided',
    'shift_reminder',
    // Sesli uyarı gereken ek operasyon olayları:
    'low_stock',
    'awaiting_payment',
    'debt_transferred',
    'order_needs_approval',
]);

export function useNotifications(pollMs = 20000) {
    const items = ref<NotificationItem[]>([]);
    const unreadCount = ref(0);
    const loading = ref(true);
    let timer: ReturnType<typeof setInterval> | null = null;

    const sound = useNotificationSound();
    const toast = useToast();

    /** null → henüz ilk yükleme yapılmadı (ilk partide ses ÇALINMAZ). */
    let seenIds: Set<number> | null = null;

    function chimeForNew(list: NotificationItem[]): void {
        if (seenIds === null) {
            // İlk yükleme: mevcut her şeyi "görüldü" say, ÇALMA/BALONCUK YOK.
            seenIds = new Set(list.map((n) => n.id));
            return;
        }
        let hasNewCritical = false;
        const fresh: NotificationItem[] = [];
        for (const n of list) {
            if (!seenIds.has(n.id)) {
                seenIds.add(n.id);
                if (!n.read) {
                    fresh.push(n);
                    if (CRITICAL_TYPES.has(n.type)) hasNewCritical = true;
                }
            }
        }
        // Tek-bip: bir refresh içinde kaç yeni gelirse gelsin en fazla bir kez.
        if (hasNewCritical) sound.beep();

        // GÖRÜNÜR BALONCUK: yeni okunmamış bildirimler ekranda toast olarak belirir
        // (önceden yalnız ses + zil rozeti vardı → kullanıcı "gelmiyor görünmüyor" dedi).
        // Bir seferde çok gelirse baloncuk selini önlemek için 3'ten sonrası özetlenir.
        if (fresh.length === 0) return;
        const shown = fresh.slice(0, 3);
        for (const n of shown) {
            toast.toast({
                variant: VARIANT_BY_TYPE[n.type] ?? 'info',
                title: n.title,
                message: n.body ?? undefined,
                url: n.url || undefined,
                // Not: backend `icon` alanı AppIcon setiyle eşleşmeyebilir → variant
                // ikonu kullanılır (her zaman geçerli). İleride eşleme yapılabilir.
                duration: 7000,
            });
        }
        if (fresh.length > shown.length) {
            toast.info(`+${fresh.length - shown.length} yeni bildirim daha`, 'Tümünü görmek için zile dokunun.');
        }
    }

    /* ---- Sekme başlığı dikkat ön-eki ---- */
    function stripCountPrefix(title: string): string {
        return title.replace(/^\(\d+\)\s+/, '');
    }

    function updateTitle(): void {
        if (typeof document === 'undefined') return;
        const base = stripCountPrefix(document.title);
        if (document.visibilityState === 'hidden' && unreadCount.value > 0) {
            document.title = `(${unreadCount.value}) ${base}`;
        } else if (document.title !== base) {
            document.title = base;
        }
    }

    async function refresh(): Promise<void> {
        try {
            const res = await api<{ unread_count: number; items: NotificationItem[] }>('/api/v1/notifications');
            items.value = res.items;
            unreadCount.value = res.unread_count;
            chimeForNew(res.items);
            updateTitle();
        } catch {
            /* zil süsleyici — hata sessiz */
        } finally {
            loading.value = false;
        }
    }

    async function markRead(id: number): Promise<void> {
        const item = items.value.find((n) => n.id === id);
        if (item && !item.read) {
            item.read = true;
            unreadCount.value = Math.max(0, unreadCount.value - 1);
            updateTitle();
        }
        try {
            await api(`/api/v1/notifications/${id}/read`, { method: 'POST' });
        } catch {
            /* iyimser güncelleme; sonraki poll düzeltir */
        }
    }

    async function markAllRead(): Promise<void> {
        items.value.forEach((n) => (n.read = true));
        unreadCount.value = 0;
        updateTitle();
        try {
            await api('/api/v1/notifications/read-all', { method: 'POST' });
        } catch {
            /* sonraki poll düzeltir */
        }
    }

    function onVisibility(): void {
        if (document.visibilityState === 'visible') {
            void refresh();
        }
        updateTitle();
    }

    onMounted(() => {
        void refresh();
        timer = setInterval(() => {
            if (document.visibilityState === 'visible') {
                void refresh();
            }
        }, pollMs);
        document.addEventListener('visibilitychange', onVisibility);
    });

    onBeforeUnmount(() => {
        if (timer) clearInterval(timer);
        document.removeEventListener('visibilitychange', onVisibility);
        // Başlığı temiz bırak (ön-eki geride bırakma).
        if (typeof document !== 'undefined') document.title = stripCountPrefix(document.title);
    });

    return { items, unreadCount, loading, refresh, markRead, markAllRead };
}
