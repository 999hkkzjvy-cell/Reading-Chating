import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { h, safeUrl } from './utils.js';

export async function initAuth() {
  const { data: { user } } = await sb.auth.getUser();
  if (user) {
    store.set('user', user);
    const { data: profile } = await sb.from('profiles').select('*').eq('id', user.id).single();
    store.set('profile', profile);
    store.set('isAdmin', profile?.role === 'admin');
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
    const initial = (profile.display_name || user.email)[0].toUpperCase();
    container.innerHTML = `
      <a href="#/profile" style="display:flex;align-items:center;gap:8px;color:var(--color-text);font-size:0.9rem;">
        <span class="avatar">${profile.avatar_url ? `<img src="${safeUrl(profile.avatar_url)}" alt="">` : h(initial)}</span>
        <span class="nav-username">${h(profile.display_name)}</span>
      </a>
      ${store.get('isAdmin') ? '<a href="#/admin" class="btn btn-outline btn-sm">管理</a>' : ''}
      <button class="btn btn-ghost btn-sm" id="btn-logout">退出</button>
    `;
    document.getElementById('btn-logout').onclick = signOut;
  } else {
    container.innerHTML = `<a href="#/login" class="btn btn-outline btn-sm">登录</a>`;
  }
}
