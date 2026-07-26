/*
 * Personel Portalı — Service Worker (kurulabilir PWA + push).
 *
 * TEK service worker portalın tüm ihtiyacını karşılar:
 *   1) Kurulabilirlik: uygulama kabuğu network-first (çevrimdışıyken cache
 *      fallback) → ana ekrana eklenebilir, hızlı yeniden açılır.
 *   2) Push: §8 push-sw.js importScripts ile dahil edilir (push +
 *      notificationclick dinleyicileri) → ayrı bir SW kaydı GEREKMEZ, kapsam
 *      çakışması olmaz. Portal push aboneliği bu SW üzerinden yapılır.
 *
 * Kapsam: portal host kökü ('/'). Panel host'unda hiç kaydedilmez.
 */

// §8 push davranışını olduğu gibi devral (push + notificationclick).
try {
    importScripts('/push-sw.js');
} catch (e) {
    /* push-sw yoksa portal yine kurulabilir kalır */
}

const CACHE = 'portal-shell-v1';
const SHELL = ['/mesaim', '/raporlarim', '/profilim', '/favicon.ico', '/portal.webmanifest'];

self.addEventListener('install', (event) => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE).then((cache) => cache.addAll(SHELL).catch(() => undefined)),
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        (async () => {
            const keys = await caches.keys();
            await Promise.all(keys.filter((k) => k !== CACHE && k.startsWith('portal-shell')).map((k) => caches.delete(k)));
            await self.clients.claim();
        })(),
    );
});

self.addEventListener('fetch', (event) => {
    const req = event.request;

    // Yalnız GET + same-origin sayfa/asset; API çağrılarına dokunma (taze veri).
    if (req.method !== 'GET') return;
    const url = new URL(req.url);
    if (url.origin !== self.location.origin) return;
    if (url.pathname.startsWith('/api/')) return;

    // Sayfa gezinmesi: network-first, çevrimdışıysa cache'ten.
    if (req.mode === 'navigate') {
        event.respondWith(
            fetch(req)
                .then((res) => {
                    const copy = res.clone();
                    caches.open(CACHE).then((cache) => cache.put(req, copy)).catch(() => undefined);
                    return res;
                })
                .catch(() => caches.match(req).then((hit) => hit || caches.match('/mesaim'))),
        );
        return;
    }

    // Diğer GET asset'leri: stale-while-revalidate.
    event.respondWith(
        caches.match(req).then((hit) => {
            const network = fetch(req)
                .then((res) => {
                    const copy = res.clone();
                    caches.open(CACHE).then((cache) => cache.put(req, copy)).catch(() => undefined);
                    return res;
                })
                .catch(() => hit);
            return hit || network;
        }),
    );
});
