/*
 * §8 Bildirim & Push — Service Worker.
 *
 * Yalnız web push içindir (uygulama cache'i / offline YOK — panel her zaman
 * çevrimiçi çalışır). 'push' olayında bildirim gösterir; tıklamada ilgili
 * panel sayfasına odaklanır/açar. Kendi kapsamı public köküdür.
 */

self.addEventListener('install', (event) => {
    // Yeni SW hemen etkinleşsin (eski sürümü bekletme).
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
    let payload = {};
    try {
        payload = event.data ? event.data.json() : {};
    } catch (e) {
        payload = { title: 'Bildirim', body: event.data ? event.data.text() : '' };
    }

    const title = payload.title || 'QR Menü';
    const options = {
        body: payload.body || '',
        icon: '/favicon.ico',
        badge: '/favicon.ico',
        // Aynı olayın (tag) tekrarı üst üste yığılmaz.
        tag: payload.tag || undefined,
        renotify: Boolean(payload.tag),
        data: { url: payload.url || '/panel' },
        timestamp: Date.now(),
    };

    event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();

    const targetUrl = (event.notification.data && event.notification.data.url) || '/panel';

    event.waitUntil(
        self.clients
            .matchAll({ type: 'window', includeUncontrolled: true })
            .then((clientList) => {
                // Açık bir panel sekmesi varsa ona odaklan + hedefe yönlendir.
                for (const client of clientList) {
                    if ('focus' in client) {
                        client.focus();
                        if ('navigate' in client && targetUrl) {
                            client.navigate(targetUrl).catch(() => {});
                        }
                        return;
                    }
                }
                // Yoksa yeni pencere aç.
                if (self.clients.openWindow) {
                    return self.clients.openWindow(targetUrl);
                }
            }),
    );
});
