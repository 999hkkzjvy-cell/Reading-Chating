import { applyPwaMode, isPwaMobile, listenPwaMode } from './pwaMode.js';

const PWA_NAV_ITEMS = [
  { path: '/', label: '首页', icon: 'home' },
  { path: '/books', label: '书库', icon: 'library' },
  { path: '/reading-circle', label: '书友圈', icon: 'messages-square' },
  { path: '/new-books', label: '新书', icon: 'sparkles' },
  { path: '/member', label: '我的', icon: 'user-round' },
];

let navElement = null;
let networkStatusElement = null;
let stopModeListener = null;
let stopNetworkListeners = null;
let networkWasOffline = false;
let recoveryTimer = null;

function cleanPath(path) {
  return String(path || '/').replace(/\?.*$/, '') || '/';
}

function itemIsActive(path, itemPath) {
  const current = cleanPath(path);
  return itemPath === '/' ? current === '/' : current === itemPath || current.startsWith(itemPath + '/');
}

function createNav() {
  const nav = document.createElement('nav');
  nav.id = 'pwa-bottom-nav';
  nav.className = 'pwa-bottom-nav';
  nav.setAttribute('aria-label', '手机端主导航');
  nav.innerHTML = PWA_NAV_ITEMS.map(({ path, label, icon }) => `
    <a href="#${path}" data-pwa-route="${path}">
      <i data-lucide="${icon}" aria-hidden="true"></i>
      <span>${label}</span>
    </a>
  `).join('');
  document.body.appendChild(nav);
  return nav;
}

function createNetworkStatus() {
  const status = document.createElement('div');
  status.id = 'pwa-network-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  status.hidden = true;
  status.innerHTML = `
    <div class="pwa-network-status-copy">
      <i data-role="pwa-network-icon" data-lucide="wifi-off" aria-hidden="true"></i>
      <span data-role="pwa-network-message"></span>
    </div>
    <button type="button" data-action="pwa-network-reload">重新加载</button>
  `;
  document.body.appendChild(status);
  return status;
}

function setNetworkStatus(state) {
  if (!networkStatusElement) return;
  const active = isPwaMobile();
  if (!active) {
    networkStatusElement.hidden = true;
    networkStatusElement.classList.remove('is-visible', 'is-recovered');
    return;
  }

  const message = networkStatusElement.querySelector('[data-role="pwa-network-message"]');
  const icon = networkStatusElement.querySelector('[data-role="pwa-network-icon"]');
  const reloadButton = networkStatusElement.querySelector('[data-action="pwa-network-reload"]');
  const offline = state === 'offline';

  networkStatusElement.dataset.state = state;
  networkStatusElement.classList.toggle('is-recovered', !offline);
  networkStatusElement.classList.add('is-visible');
  networkStatusElement.hidden = false;
  if (message) message.textContent = offline
    ? '当前离线，数据不会更新，未提交内容不会被覆盖。'
    : '网络已恢复，可以重新加载最新内容。';
  if (icon) icon.setAttribute('data-lucide', offline ? 'wifi-off' : 'wifi');
  if (reloadButton) reloadButton.hidden = offline;
  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function syncNetworkStatus() {
  if (!networkStatusElement) return;
  const online = typeof navigator === 'undefined' || navigator.onLine !== false;
  if (!online) {
    networkWasOffline = true;
    setNetworkStatus('offline');
  } else if (networkWasOffline) {
    setNetworkStatus('online');
    clearTimeout(recoveryTimer);
    recoveryTimer = setTimeout(() => {
      if (networkStatusElement) {
        networkStatusElement.hidden = true;
        networkStatusElement.classList.remove('is-visible', 'is-recovered');
      }
      networkWasOffline = false;
    }, 7000);
  } else {
    setNetworkStatus('online');
    networkStatusElement.hidden = true;
    networkStatusElement.classList.remove('is-visible', 'is-recovered');
  }
}

function bindNetworkStatusEvents() {
  const onOffline = () => {
    networkWasOffline = true;
    clearTimeout(recoveryTimer);
    setNetworkStatus('offline');
  };
  const onOnline = () => syncNetworkStatus();
  const onClick = event => {
    if (!event.target.closest('[data-action="pwa-network-reload"]')) return;
    event.preventDefault();
    window.location.reload();
  };

  window.addEventListener('offline', onOffline);
  window.addEventListener('online', onOnline);
  document.addEventListener('click', onClick);
  stopNetworkListeners = () => {
    window.removeEventListener('offline', onOffline);
    window.removeEventListener('online', onOnline);
    document.removeEventListener('click', onClick);
    clearTimeout(recoveryTimer);
  };
}

function syncVisibility() {
  if (!navElement) return;
  const active = isPwaMobile();
  navElement.classList.toggle('is-active', active);
  navElement.setAttribute('aria-hidden', String(!active));
  navElement.querySelectorAll('a').forEach((link) => {
    link.tabIndex = active ? 0 : -1;
  });
  if (networkStatusElement && !active) {
    networkStatusElement.hidden = true;
    networkStatusElement.classList.remove('is-visible', 'is-recovered');
  }
}

export function syncPwaShell(path) {
  if (!navElement) return;
  syncVisibility();
  const currentPath = cleanPath(path || (location.hash.slice(1) || '/'));
  navElement.querySelectorAll('[data-pwa-route]').forEach((link) => {
    const active = itemIsActive(currentPath, link.dataset.pwaRoute);
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  });
}

export function initPwaShell() {
  if (typeof document === 'undefined' || navElement) return;
  applyPwaMode();
  navElement = createNav();
  networkStatusElement = createNetworkStatus();
  bindNetworkStatusEvents();
  syncPwaShell(location.hash.slice(1) || '/');
  stopModeListener = listenPwaMode(() => {
    syncPwaShell(location.hash.slice(1) || '/');
    syncNetworkStatus();
  });
  syncNetworkStatus();
  if (typeof lucide !== 'undefined') lucide.createIcons({ attrs: { 'stroke-width': 1.8 } });
}

export function disposePwaShell() {
  if (stopModeListener) stopModeListener();
  if (stopNetworkListeners) stopNetworkListeners();
  stopModeListener = null;
  stopNetworkListeners = null;
  if (navElement) navElement.remove();
  if (networkStatusElement) networkStatusElement.remove();
  navElement = null;
  networkStatusElement = null;
  networkWasOffline = false;
}
