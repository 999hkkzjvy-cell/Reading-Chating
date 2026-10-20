import { initAuth } from './auth.js';
import { authDiagnosticReport } from './authDiagnostics.js';
import { store } from './store.js';
import { router } from './router.js?v=page-load-20261021-1';

let bound = false;
let slowTimer;
let retryPending = false;

export function refreshAuthDiagnostics() {
  document.querySelectorAll('[data-auth-diagnostics]').forEach(el => {
    el.textContent = authDiagnosticReport();
  });
}

export function bindAuthFeedback() {
  if (bound) return;
  const panel = document.getElementById('auth-status-panel');
  if (!panel) return; // An older cached HTML shell must not prevent app startup.
  bound = true;
  const message = panel.querySelector('[data-auth-message]');
  const retry = panel.querySelector('[data-auth-retry]');
  function update() {
    clearTimeout(slowTimer);
    const status = store.get('authStatus');
    panel.hidden = true;
    retry.hidden = false;
    retry.disabled = retryPending;
    if (status === 'uncertain' || status === 'profile-unavailable') {
      message.textContent = status === 'uncertain'
        ? '暂时无法确认登录状态，请检查网络后重试。已有登录信息不会因本次连接失败被主动清除。'
        : '身份已确认，但个人资料暂未加载完成。可重试读取，无需再次输入密码。';
      panel.hidden = false;
    } else if (['checking', 'signing-in', 'profile-loading'].includes(status)) {
      slowTimer = setTimeout(() => {
        message.textContent = status === 'profile-loading'
          ? '身份已确认，个人资料仍在加载。可以切换到可用网络后继续等待。'
          : '登录服务响应较慢，仍在等待结果。可以切换网络；请勿重复提交密码。';
        retry.hidden = true;
        panel.hidden = false;
        refreshAuthDiagnostics();
      }, 12000);
    }
    refreshAuthDiagnostics();
  }
  store.on('authStatus', update);
  document.addEventListener('toggle', event => {
    if (event.target.matches?.('details.auth-diagnostics') && event.target.open) refreshAuthDiagnostics();
  }, true);
  retry.addEventListener('click', async () => {
    if (retryPending) return;
    retryPending = true;
    retry.disabled = true;
    try {
      await initAuth();
      const path = router.currentPath();
      if (path.replace(/\?.*$/, '') === '/login' && store.get('user') &&
          ['ready', 'profile-unavailable'].includes(store.get('authStatus'))) {
        const redirect = new URLSearchParams(path.split('?')[1] || '').get('redirect') || '/';
        router.navigate(redirect.startsWith('/') && !redirect.startsWith('//') ? redirect : '/');
      }
    } catch { /* The state and the diagnostic panel show the result. */ }
    finally {
      retryPending = false;
      update();
    }
  });
  update();
}
