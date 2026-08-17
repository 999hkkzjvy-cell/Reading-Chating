const SERVICE_WORKER_URL = '/sw.js?v=20260818-1';

/**
 * Register after the page is ready so PWA support never blocks the first
 * render. The worker itself is network-first for navigations and only owns a
 * tiny offline shell cache.
 */
export function registerPwaServiceWorker() {
  if (typeof window === 'undefined' || !('serviceWorker' in navigator)) {
    return Promise.resolve(null);
  }

  if (!window.isSecureContext) return Promise.resolve(null);

  const register = () => navigator.serviceWorker.register(SERVICE_WORKER_URL, {
    scope: '/',
    updateViaCache: 'none'
  }).then(registration => {
    registration.update().catch(() => {});
    return registration;
  }).catch(() => null);

  if (document.readyState === 'complete') return register();

  return new Promise(resolve => {
    window.addEventListener('load', () => resolve(register()), { once: true });
  });
}
