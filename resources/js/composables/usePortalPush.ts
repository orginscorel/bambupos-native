/**
 * Personel Portalı Web Push aboneliği (VAPID) — tarayıcı tarafı.
 *
 * usePush ile AYNI backend uçlarını (/api/v1/push/*) kullanır ama service
 * worker olarak `/portal-sw.js`'i kaydeder (push-sw.js'i importScripts ile
 * içerir) → portalın tek SW'si; §8 push SW'siyle KAPSAM ÇAKIŞMAZ.
 *
 * iOS NOTU: push yalnız ana ekrana eklenmiş (standalone PWA) Safari'de çalışır.
 */
import { onMounted, ref } from 'vue';
import { api } from '@/lib/http';

type PermissionState = 'default' | 'granted' | 'denied' | 'unsupported';

function base64ToUint8Array(base64: string): Uint8Array {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const raw = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/');
    const decoded = atob(raw);
    const output = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i += 1) {
        output[i] = decoded.charCodeAt(i);
    }
    return output;
}

export function usePortalPush() {
    const supported = ref(false);
    const permission = ref<PermissionState>('default');
    const subscribed = ref(false);
    const busy = ref(false);

    function detectSupport(): boolean {
        return (
            typeof window !== 'undefined' &&
            'serviceWorker' in navigator &&
            'PushManager' in window &&
            'Notification' in window
        );
    }

    async function registration(): Promise<ServiceWorkerRegistration> {
        return navigator.serviceWorker.register('/portal-sw.js', { scope: '/' });
    }

    async function refreshState(): Promise<void> {
        supported.value = detectSupport();
        if (!supported.value) {
            permission.value = 'unsupported';
            return;
        }
        permission.value = Notification.permission as PermissionState;
        try {
            const reg = await navigator.serviceWorker.getRegistration('/');
            const sub = reg ? await reg.pushManager.getSubscription() : null;
            subscribed.value = sub !== null;
        } catch {
            subscribed.value = false;
        }
    }

    /** Push'u aç: izin iste → abone ol → backend'e kaydet. Başarıyı döndürür. */
    async function enable(): Promise<boolean> {
        if (!detectSupport()) {
            permission.value = 'unsupported';
            return false;
        }
        busy.value = true;
        try {
            const perm = await Notification.requestPermission();
            permission.value = perm as PermissionState;
            if (perm !== 'granted') {
                return false;
            }

            const keyInfo = await api<{ key: string; enabled: boolean }>('/api/v1/push/vapid-public-key');
            if (!keyInfo.key || !keyInfo.enabled) {
                return false;
            }

            const reg = await registration();
            await navigator.serviceWorker.ready;

            let sub = await reg.pushManager.getSubscription();
            if (!sub) {
                sub = await reg.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: base64ToUint8Array(keyInfo.key) as unknown as BufferSource,
                });
            }

            const json = sub.toJSON() as { endpoint?: string; keys?: { p256dh?: string; auth?: string } };
            await api('/api/v1/push/subscribe', {
                method: 'POST',
                body: {
                    endpoint: json.endpoint,
                    keys: { p256dh: json.keys?.p256dh, auth: json.keys?.auth },
                },
            });

            subscribed.value = true;
            return true;
        } catch {
            return false;
        } finally {
            busy.value = false;
        }
    }

    /** Push'u kapat: aboneliği kaldır + backend'den sil. */
    async function disable(): Promise<void> {
        busy.value = true;
        try {
            const reg = await navigator.serviceWorker.getRegistration('/');
            const sub = reg ? await reg.pushManager.getSubscription() : null;
            if (sub) {
                const endpoint = (sub.toJSON() as { endpoint?: string }).endpoint;
                await sub.unsubscribe().catch(() => {});
                if (endpoint) {
                    await api('/api/v1/push/unsubscribe', { method: 'POST', body: { endpoint } }).catch(() => {});
                }
            }
            subscribed.value = false;
        } finally {
            busy.value = false;
        }
    }

    onMounted(refreshState);

    return { supported, permission, subscribed, busy, enable, disable, refreshState };
}
