const STANDALONE_QUERY = '(display-mode: standalone)';
const MOBILE_QUERY = '(max-width: 768px)';

function mediaMatches(query) {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia(query).matches;
}

/**
 * Detect an installed PWA window. iOS exposes navigator.standalone instead of
 * display-mode, so both signals are supported here.
 */
export function isStandaloneMode() {
  return mediaMatches(STANDALONE_QUERY)
    || (typeof navigator !== 'undefined' && navigator.standalone === true);
}

export function isPwaMobile() {
  if (!isStandaloneMode()) return false;
  return mediaMatches(MOBILE_QUERY)
    || (typeof window !== 'undefined' && window.innerWidth <= 768);
}

export function applyPwaMode() {
  if (typeof document === 'undefined') return 'browser';
  const mode = isPwaMobile() ? 'pwa-mobile' : 'browser';
  document.documentElement.dataset.appMode = mode;
  return mode;
}

/** Keep the data attribute correct when a standalone window is resized. */
export function listenPwaMode(onChange) {
  if (typeof window === 'undefined') return () => {};
  const mobileQuery = typeof window.matchMedia === 'function'
    ? window.matchMedia(MOBILE_QUERY)
    : null;
  const standaloneQuery = typeof window.matchMedia === 'function'
    ? window.matchMedia(STANDALONE_QUERY)
    : null;
  const update = () => {
    const mode = applyPwaMode();
    if (typeof onChange === 'function') onChange(mode);
  };
  const add = (query) => {
    if (!query) return;
    if (typeof query.addEventListener === 'function') query.addEventListener('change', update);
    else if (typeof query.addListener === 'function') query.addListener(update);
  };
  const remove = (query) => {
    if (!query) return;
    if (typeof query.removeEventListener === 'function') query.removeEventListener('change', update);
    else if (typeof query.removeListener === 'function') query.removeListener(update);
  };
  add(mobileQuery);
  add(standaloneQuery);
  window.addEventListener('resize', update, { passive: true });
  return () => {
    remove(mobileQuery);
    remove(standaloneQuery);
    window.removeEventListener('resize', update);
  };
}
