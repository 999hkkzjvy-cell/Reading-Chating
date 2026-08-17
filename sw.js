/*
 * Reading-Chating PWA service worker.
 *
 * This worker deliberately has a small cache boundary: it stores only the
 * offline shell and install metadata. Supabase, Edge Functions, uploads and
 * all non-GET requests stay on the network and are never cached here.
 *
 * Kill-switch: deploy this file with ENABLE_SERVICE_WORKER = false when a
 * remote rollback must stop old installed PWAs from using this worker. The
 * active worker removes its own caches and unregisters during activation.
 */
const SW_VERSION = '20260818-1';
const CACHE_NAME = `reading-chating-pwa-${SW_VERSION}`;
const ENABLE_SERVICE_WORKER = true;
const OFFLINE_URL = '/offline.html';
const PRECACHE_URLS = [
  OFFLINE_URL,
  '/manifest.webmanifest',
  '/assets/pwa/icon.svg',
  '/assets/pwa/icon-192.png',
  '/assets/pwa/icon-512.png'
];

async function clearWorkerCaches() {
  const cacheNames = await caches.keys();
  await Promise.all(
    cacheNames
      .filter(name => name.startsWith('reading-chating-pwa-'))
      .map(name => caches.delete(name))
  );
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    if (!ENABLE_SERVICE_WORKER) {
      await self.skipWaiting();
      return;
    }

    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(PRECACHE_URLS);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    if (!ENABLE_SERVICE_WORKER) {
      await clearWorkerCaches();
      await self.registration.unregister();
      return;
    }

    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter(name => name.startsWith('reading-chating-pwa-') && name !== CACHE_NAME)
        .map(name => caches.delete(name))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  if (event.data?.type === 'PWA_SW_SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Keep future same-origin APIs and server-side routes network-only too.
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/functions/')) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request, { cache: 'no-store' })
        .catch(async () => {
          const offlineResponse = await caches.match(OFFLINE_URL);
          return offlineResponse || new Response('暂时没有网络', {
            status: 503,
            headers: { 'Content-Type': 'text/plain; charset=utf-8' }
          });
        })
    );
    return;
  }

  // Only exact precache entries may be served from the cache. Query strings
  // are ignored so versioned asset URLs remain compatible with the shell.
  if (PRECACHE_URLS.includes(url.pathname)) {
    event.respondWith(
      caches.match(request, { ignoreSearch: true }).then(cached => {
        if (cached) return cached;
        return fetch(request);
      })
    );
  }
});
