import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { loadMemberSummary } from './members.js';
import { esc, formatDateTime, h, safeUrl } from './utils.js';
import { authStep } from './authDiagnostics.js';

const PASSWORD_RECOVERY_PENDING_KEY = 'password_recovery_pending';
let authRevision = 0;
let restorePromise = null;

sb.auth.onAuthStateChange((event, session) => {
  if (event === 'PASSWORD_RECOVERY' && session?.user?.id) {
    sessionStorage.setItem(PASSWORD_RECOVERY_PENDING_KEY, session.user.id);
    setTimeout(() => {
      if (sessionStorage.getItem(PASSWORD_RECOVERY_PENDING_KEY) === session.user.id) {
        window.dispatchEvent(new CustomEvent('password-recovery-started'));
      }
    }, 0);
  }
});

export function initAuth() {
  if (restorePromise) return restorePromise;
  const revision = authRevision;
  const pending = restoreAuth(revision).finally(() => {
    if (restorePromise === pending) restorePromise = null;
  });
  restorePromise = pending;
  return pending;
}

async function restoreAuth(revision) {
  store.set('authStatus', 'checking');
  try {
    const { data: { user } } = await authStep('restore', () => sb.auth.getUser());
    if (revision !== authRevision) return;
    if (!user) {
      clearAuthStore();
      return;
    }
    await acceptVerifiedUser(user, revision);
  } catch (error) {
    if (revision !== authRevision) return;
    if (error?.name === 'AuthSessionMissingError' || error?.code === 'session_not_found') {
      clearAuthStore();
      return;
    }
    // A failed request does not establish that a saved session is invalid.
    store.set('authStatus', 'uncertain');
    renderNavUser();
    throw error;
  }
}

async function acceptVerifiedUser(user, revision) {
  if (revision !== authRevision) return;
  if (store.get('user')?.id !== user.id) {
    store.set('profile', null);
    store.set('member', null);
  }
  store.set('user', user);
  store.set('isAdmin', false);
  store.set('isBanned', null);
  store.set('authStatus', 'profile-loading');
  renderNavUser();
  try {
    const { data: profile } = await authStep('profile', () =>
      sb.from('profiles').select('*').eq('id', user.id).single());
    if (revision !== authRevision) return;
    store.set('profile', profile);
    store.set('isAdmin', profile?.role === 'admin');
    store.set('authStatus', profile ? 'ready' : 'profile-unavailable');
  } catch {
    if (revision !== authRevision) return;
    // Identity was verified by Auth; a profile failure is not a password failure.
    store.set('authStatus', 'profile-unavailable');
  }
  renderNavUser();
  loadMemberSummary(user.id).catch(() => {});
}

export function checkLoginRateLimit() {
  const now = Date.now();
  const key = 'login_attempts';
  let record;
  try {
    record = JSON.parse(sessionStorage.getItem(key) || 'null');
  } catch (e) {
    record = { count: 0, until: 0 };
  }
  if (!record || !Number.isInteger(record.count) || record.count < 0 ||
      !Number.isFinite(record.until) ||
      (record.lastAttempt && now - record.lastAttempt > 900000 && record.until <= now)) {
    record = { count: 0, until: 0 };
  }
  if (record.until > now) {
    return { blocked: true, count: record.count, remaining: Math.ceil((record.until - now) / 1000) };
  }
  return { blocked: false, count: record.count };
}

export function recordLoginAttempt(success) {
  const now = Date.now();
  const record = checkLoginRateLimit();
  if (success) {
    try { sessionStorage.removeItem('login_attempts'); } catch { /* Storage may be unavailable. */ }
    return;
  }
  if (record.blocked) return;
  const count = record.count + 1;
  let until = 0;
  if (count >= 10) until = now + 300000;
  else if (count >= 5) until = now + 60000;
  else if (count >= 3) until = now + 15000;
  try {
    sessionStorage.setItem('login_attempts', JSON.stringify({ count, until, lastAttempt: now }));
  } catch { /* This local UX cooldown is not a server-side security boundary. */ }
}

export async function signIn(email, password) {
  const revision = ++authRevision;
  restorePromise = null;
  const previousStatus = store.get('authStatus');
  store.set('authStatus', 'signing-in');
  let data;
  try {
    ({ data } = await authStep('password', () => sb.auth.signInWithPassword({ email, password })));
  } catch (error) {
    if (revision === authRevision) {
      const rejected = ['invalid_credentials', 'email_not_confirmed'].includes(error?.code);
      store.set('authStatus', rejected
        ? (store.get('user') ? previousStatus : 'anonymous')
        : 'uncertain');
      renderNavUser();
    }
    throw error;
  }
  if (!data?.user?.id || !data?.session) {
    store.set('authStatus', 'uncertain');
    throw new Error('Auth returned no session');
  }
  // This user came from the successful password exchange, not unverified storage.
  // Avoid an unnecessary second Auth round trip after accepting the password.
  await acceptVerifiedUser(data.user, revision);
}

export async function signUp(email, password, displayName) {
  const { error } = await sb.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName } }
  });
  if (error) throw error;
  toast('注册成功！请检查邮箱验证链接。');
}

export async function signOut() {
  await sb.auth.signOut();
  clearPasswordRecoveryPending();
  clearAuthStore();
  location.hash = '#/';
}

function clearAuthStore() {
  authRevision++;
  store.set('user', null);
  store.set('profile', null);
  store.set('member', null);
  store.set('isAdmin', false);
  store.set('isBanned', null);
  store.set('authStatus', 'anonymous');
  renderNavUser();
}

export async function resetPassword(email) {
  const { error } = await sb.auth.resetPasswordForEmail(email, {
    redirectTo: passwordResetRedirectUrl()
  });
  if (error) throw error;
}

function passwordResetRedirectUrl() {
  const url = new URL(window.location.href);
  url.search = '';
  url.hash = '';
  url.searchParams.set('auth_action', 'reset-password');
  return url.toString();
}

function hashHasRecoveryMarker(hash) {
  if (!hash) return false;
  const raw = hash.startsWith('#') ? hash.slice(1) : hash;
  if (raw.startsWith('/reset-password')) return true;

  const queryStart = raw.indexOf('?');
  const paramText = queryStart >= 0 ? raw.slice(queryStart + 1) : raw;
  return new URLSearchParams(paramText).get('type') === 'recovery';
}

function hasAuthRedirectError(url) {
  return url.searchParams.has('error') ||
    new URLSearchParams(url.hash.replace(/^#/, '')).has('error');
}

export function getAuthRedirectRoute() {
  const url = new URL(window.location.href);
  if (hasAuthRedirectError(url)) {
    clearPasswordRecoveryPending();
    return url.searchParams.get('auth_action') === 'reset-password' ||
      url.searchParams.get('type') === 'recovery' || hashHasRecoveryMarker(url.hash)
      ? '/reset-password' : null;
  }
  if (sessionStorage.getItem(PASSWORD_RECOVERY_PENDING_KEY)) return '/reset-password';
  if (url.searchParams.get('auth_action') === 'reset-password') return '/reset-password';
  if (url.searchParams.get('type') === 'recovery') return '/reset-password';
  if (hashHasRecoveryMarker(url.hash)) return '/reset-password';
  return null;
}

export function replaceAuthRedirectRoute(routePath) {
  const url = new URL(window.location.href);
  url.searchParams.delete('auth_action');
  url.searchParams.delete('code');
  url.searchParams.delete('type');
  url.searchParams.delete('error');
  url.searchParams.delete('error_code');
  url.searchParams.delete('error_description');
  url.hash = '#' + routePath;
  window.history.replaceState(null, '', url.toString());
}

export function clearPasswordRecoveryPending() {
  sessionStorage.removeItem(PASSWORD_RECOVERY_PENDING_KEY);
}

export async function hasPasswordRecoverySession() {
  const recoveryUserId = sessionStorage.getItem(PASSWORD_RECOVERY_PENDING_KEY);
  if (!recoveryUserId) return false;
  const { data: { session }, error } = await sb.auth.getSession();
  return !error && session?.user?.id === recoveryUserId;
}

export async function updatePassword(newPassword) {
  const { error } = await sb.auth.updateUser({ password: newPassword });
  if (error) throw error;
  toast('密码已重置，请重新登录。');
}

export async function completePasswordReset(newPassword) {
  if (!await hasPasswordRecoverySession()) {
    const error = new Error('Password recovery session missing');
    error.code = 'recovery_session_missing';
    throw error;
  }
  const { error } = await sb.auth.updateUser({ password: newPassword });
  if (error) throw error;

  sessionStorage.removeItem(PASSWORD_RECOVERY_PENDING_KEY);
  await sb.auth.signOut();
  clearAuthStore();
  toast('密码已重置，请重新登录。');
}

export function renderNavUser() {
  const user = store.get('user');
  const container = document.getElementById('nav-user');
  if (!container) return;
  if (user) {
    container.innerHTML = `
      ${store.get('isAdmin') ? '<a href="#/admin" class="btn btn-outline btn-sm">管理</a>' : ''}
      <a href="#/member" class="nav-user-link">个人中心</a>
      <button class="btn-bell" id="btn-bell" title="消息通知">
        <i data-lucide="bell"></i>
        <span class="bell-dot" id="bell-dot" style="display:none;"></span>
      </button>
    `;
    document.getElementById('btn-bell').onclick = toggleNotificationPanel;
    if (typeof lucide !== 'undefined') lucide.createIcons();
    refreshUnreadBadge();
  } else {
    const label = store.get('authStatus') === 'uncertain' ? '确认登录状态' : '登录';
    container.innerHTML = `<a href="#/login" class="btn btn-outline btn-sm">${label}</a>`;
  }
}

// ---- 通知面板 ----

async function refreshUnreadBadge() {
  const dot = document.getElementById('bell-dot');
  if (!dot) return;
  const { data } = await sb.rpc('get_unread_notification_count');
  if (data > 0) {
    dot.style.display = '';
  } else {
    dot.style.display = 'none';
  }
}

function notificationHashLink(n) {
  if (n.link_path) return `#${n.link_path}`;
  if (n.post_id) return `#/reading-circle?post=${encodeURIComponent(n.post_id)}`;
  return '#/member';
}

function renderActorLink(n) {
  if (!n.actor_id) return h(n.actor_name || '书友');
  return `<a href="#/user/${h(n.actor_id)}" class="notification-name-link" data-action="close-notification">${h(n.actor_name || '书友')}</a>`;
}

function renderNotificationCopy(n) {
  if (n.message && (n.type === 'level_badge' || n.type === 'follow')) {
    if (n.type === 'follow') {
      return `${renderActorLink(n)}关注了你`;
    }
    return h(n.message);
  }

  if (n.type === 'follow') {
    return `${renderActorLink(n)}关注了你`;
  }

  if (n.type === 'level_badge') {
    return h(n.message || '你获得了新的会员徽章，快去个人中心看看吧！');
  }

  return `
    ${renderActorLink(n)}
    给您关于<em>《${h(n.book_title || '未知书目')}》</em>的${n.type === 'comment_reply' ? '评论留了评论' : `书友圈${n.type === 'like' ? '点了赞' : '留了评论'}`}
  `;
}

function renderNotificationItem(n) {
  const target = notificationHashLink(n);
  const actionText = n.type === 'level_badge' ? '去看看' : n.type === 'follow' ? '查看主页' : '查看详情';
  return `
    <div class="notification-item ${n.is_read ? 'read' : 'unread'}">
      <a href="#/user/${h(n.actor_id)}" class="notification-avatar notification-user-link" data-action="close-notification">${n.actor_avatar ? `<img src="${safeUrl(n.actor_avatar)}" alt="">` : h((n.actor_name || '?')[0])}</a>
      <div class="notification-body">
        <p>${renderNotificationCopy(n)}</p>
        <span>${h(formatDateTime(n.created_at))}</span>
      </div>
      <a href="${h(target)}" class="btn btn-sm btn-outline notification-detail-btn" data-action="close-notification">${actionText}</a>
    </div>
  `;
}

async function toggleNotificationPanel() {
  let panel = document.getElementById('notification-panel');
  if (panel) {
    panel.remove();
    return;
  }

  const { data: notifications } = await sb.rpc('get_notifications', { p_limit: 20 });

  panel = document.createElement('div');
  panel.id = 'notification-panel';
  panel.className = 'notification-panel';

  let unseenIds = [];

  if (!notifications || !notifications.length) {
    panel.innerHTML = '<div class="notification-empty"><i data-lucide="bell-off"></i><p>暂无消息</p></div>';
  } else {
    unseenIds = notifications.filter(n => !n.is_read).map(n => n.id);

    panel.innerHTML = `
      <div class="notification-head">
        <span>消息通知</span>
        ${unseenIds.length > 0 ? `<button class="btn-read-all" data-action="mark-all-read">全部已读</button>` : ''}
      </div>
      <div class="notification-list">
        ${notifications.map(renderNotificationItem).join('')}
      </div>
    `;
  }

  document.body.appendChild(panel);

  // 点击外部关闭
  setTimeout(() => {
    document.addEventListener('click', closePanelOnOutside, { once: true });
  }, 0);

  // 标记已读
  if (unseenIds.length > 0) {
    await sb.rpc('mark_notifications_read', { p_ids: unseenIds });
    panel.querySelectorAll('.notification-item.unread').forEach(item => {
      item.classList.remove('unread');
      item.classList.add('read');
    });
    panel.querySelector('[data-action="mark-all-read"]')?.remove();
    refreshUnreadBadge();
  }

  if (typeof lucide !== 'undefined') lucide.createIcons();
}

function closePanelOnOutside(e) {
  const panel = document.getElementById('notification-panel');
  const bell = document.getElementById('btn-bell');
  if (panel && !panel.contains(e.target) && e.target !== bell && !bell?.contains(e.target)) {
    panel.remove();
  } else {
    document.addEventListener('click', closePanelOnOutside, { once: true });
  }
}

export async function bindNotificationEvents() {
  document.addEventListener('click', async e => {
    const markAllBtn = e.target.closest('[data-action="mark-all-read"]');
    if (markAllBtn) {
      await sb.rpc('mark_all_notifications_read');
      document.getElementById('notification-panel')?.remove();
      refreshUnreadBadge();
      return;
    }

    const closeBtn = e.target.closest('[data-action="close-notification"]');
    if (closeBtn) {
      document.getElementById('notification-panel')?.remove();
      return;
    }
  });
}
