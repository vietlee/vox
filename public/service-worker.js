// VOX PWA service worker — network-first with offline fallback + push notifications.
const CACHE = 'vox-v13';
const OFFLINE_ASSETS = ['/icon-192.png', '/icon-512.png', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(OFFLINE_ASSETS)).catch(() => {}));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Only handle same-origin GET navigations/assets; let everything else (POST/AJAX, cross-origin) go straight to network.
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

  // HTML documents — ALWAYS network-first, and never cached. This covers both
  // full navigations (req.mode === 'navigate') AND Turbo Drive page fetches
  // (which use a non-navigate mode and were previously served stale from cache,
  // so layout/logic changes never reached installed PWAs).
  const accept = req.headers.get('accept') || '';
  const isHTML = req.mode === 'navigate' ||
                 req.destination === 'document' ||
                 accept.indexOf('text/html') !== -1;
  if (isHTML) {
    event.respondWith(
      fetch(req).catch(() => caches.match(req).then((r) => r || caches.match('/icon-192.png')))
    );
    return;
  }

  // Static assets: cache-first with background refresh.
  event.respondWith(
    caches.match(req).then((cached) => {
      const fetched = fetch(req).then((res) => {
        if (res && res.status === 200) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || fetched;
    })
  );
});

// Push notification handler
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? JSON.parse(event.data.text()) : {}; } catch(e) {}

  const title   = data.title || 'VOX';
  const options = {
    body:  data.body  || 'Đến lúc học rồi!',
    icon:  data.icon  || '/icon-192.png',
    badge: '/icon-192.png',
    data:  { url: data.url || '/learner/dashboard' },
    vibrate: [200, 100, 200]
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Click on notification opens the app at the specified URL
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : '/learner/dashboard';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
