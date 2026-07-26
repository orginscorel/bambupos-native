/**
 * §8 Panel-içi bildirim zili — okunmamış sayısı + liste + okundu işaretleme.
 * Hafif poll (varsayılan 20 sn). Sekme gizliyken yoklamaz (görünürlük).
 */
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { api } from '@/lib/http';

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

export function useNotifications(pollMs = 20000) {
    const items = ref<NotificationItem[]>([]);
    const unreadCount = ref(0);
    const loading = ref(true);
    let timer: ReturnType<typeof setInterval> | null = null;

    async function refresh(): Promise<void> {
        try {
            const res = await api<{ unread_count: number; items: NotificationItem[] }>('/api/v1/notifications');
            items.value = res.items;
            unreadCount.value = res.unread_count;
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
    });

    return { items, unreadCount, loading, refresh, markRead, markAllRead };
}
