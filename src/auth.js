import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { loadMemberSummary } from './members.js';
import { esc, formatDateTime, h, safeUrl } from './utils.js';

export async function initAuth() {
  const { data: { user } } = await sb.auth.getUser();
  if (user) {
    store.set('user', user);
    const { data: profile } = await sb.from('profiles').select('*').eq('id', user.id).single();
    store.set('profile', profile);
    store.set('isAdmin', profile?.role === 'admin');
    await loadMemberSummary(user.id);
  }
  renderNavUser();
}

export function checkLoginRateLimit() {
  const now = Date.now();
  const key = 'login_attempts';
  let record;
  try {
    record = JSON.parse(sessionStorage.getItem(key) || '{"count":0,"until":0}');
  } catch (e) {
    record = { count: 0, until: 0 };
  }
  if (record.until > now) {
    return { blocked: true, remaining: Math.ceil((record.until - now) / 1000) };
  }
  return { blocked: false, count: record.count };
}

export function recordLoginAttempt(success) {
  const now = Date.now();
  const record = checkLoginRateLimit();
  if (success) {
    sessionStorage.removeItem('login_attempts');
    return;
  }
  const count = record.count + 1;
  let until = 0;
  if (count >= 10) until = now + 300000;
  else if (count >= 5) until = now + 60000;
  else if (count >= 3) until = now + 15000;
  sessionStorage.setItem('login_attempts', JSON.stringify({ count, until }));
}

export async function signIn(email, password) {
  const { error } = await sb.auth.signInWithPassword({ email, password });
  if (error) throw error;
  await initAuth();
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
  store.set('user', null);
  store.set('profile', null);
  store.set('member', null);
  store.set('isAdmin', false);
  renderNavUser();
  location.hash = '#/';
}

export async function resetPassword(email) {
  const { error } = await sb.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.origin + window.location.pathname + '#/reset-password'
  });
  if (error) throw error;
  toast('密码重置邮件已发送，请检查邮箱。');
}

export async function updatePassword(newPassword) {
  const { error } = await sb.auth.updateUser({ password: newPassword });
  if (error) throw error;
  toast('密码已重置，请重新登录。');
}

export function renderNavUser() {
  const user = store.get('user');
  const profile = store.get('profile');
  const container = document.getElementById('nav-user');
  if (user && profile) {
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
    container.innerHTML = `<a href="#/login" class="btn btn-outline btn-sm">登录</a>`;
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
        ${notifications.map(n => `
          <div class="notification-item ${n.is_read ? 'read' : 'unread'}">
            <div class="notification-avatar">${n.actor_avatar ? `<img src="${safeUrl(n.actor_avatar)}" alt="">` : h((n.actor_name || '?')[0])}</div>
            <div class="notification-body">
              <p>
                <strong>${h(n.actor_name)}</strong>
                给您关于<em>《${h(n.book_title || '未知书目')}》</em>的书友圈${n.type === 'like' ? '点了赞' : '留了评论'}
              </p>
              <span>${h(formatDateTime(n.created_at))}</span>
            </div>
            <a href="#/reading-circle?post=${h(n.post_id)}" class="btn btn-sm btn-outline notification-detail-btn" data-action="close-notification">查看详情</a>
          </div>
        `).join('')}
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
