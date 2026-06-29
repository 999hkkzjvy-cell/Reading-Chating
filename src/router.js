import { sb } from './supabaseClient.js';
import { store } from './store.js';

const routes = {};
let afterRouteRender = () => {};

export function route(path, handler, opts = {}) {
  routes[path] = { handler, ...opts };
}

export function setAfterRouteRender(fn) {
  afterRouteRender = fn || (() => {});
}

export const router = {
  navigate(path) {
    location.hash = '#' + path;
  },

  currentPath() {
    return location.hash.slice(1) || '/';
  },

  match(path) {
    for (const [pattern, def] of Object.entries(routes)) {
      const keys = [];
      const regexStr = pattern.replace(/:(\w+)/g, (_, k) => {
        keys.push(k);
        return '([^/]+)';
      });
      const match = path.match(new RegExp('^' + regexStr + '$'));
      if (match) {
        const params = {};
        keys.forEach((k, i) => {
          params[k] = match[i + 1];
        });
        return { ...def, params };
      }
    }
    return null;
  },

  async render() {
    try {
      const path = this.currentPath();
      const matched = this.match(path);

      const authRequired = ['/member', '/profile', '/profile/edit', '/reading-circle/mine', '/admin'].some(p => path.startsWith(p));
      if (authRequired && !store.get('user')) {
        return this.navigate('/login?redirect=' + encodeURIComponent(path));
      }

      if (path.startsWith('/admin')) {
        const user = store.get('user');
        if (!user) {
          return this.navigate('/login?redirect=' + encodeURIComponent(path));
        }
        const { data: profile } = await sb.from('profiles').select('role').eq('id', user.id).single();
        if (profile?.role !== 'admin') {
          document.getElementById('view').innerHTML = '<div class="container section"><div class="empty-state"><i data-lucide="shield-alert"></i><p>您没有管理权限</p></div></div>';
          lucide.createIcons();
          return;
        }
      }

      if (matched) {
        document.getElementById('view').innerHTML = await matched.handler(matched.params);
        window.scrollTo(0, 0);
      } else {
        document.getElementById('view').innerHTML = '<div class="container section"><div class="empty-state"><i data-lucide="file-question"></i><p>页面未找到</p></div></div>';
      }

      afterRouteRender(path);
    } catch (err) {
      console.error('Router error:', err);
      const errText = String(err.message || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
      document.getElementById('view').innerHTML = '<div class="container section"><div class="empty-state"><p>⚠️ 加载失败：' + errText + '</p><p style="font-size:0.85rem;color:var(--color-text-3);">请检查网络连接或刷新重试</p></div></div>';
      if (typeof lucide !== 'undefined') lucide.createIcons();
    }
  },

  updateNav(path) {
    document.querySelectorAll('#nav-links a').forEach(a => {
      a.classList.toggle('active', a.dataset.route && path.startsWith(a.dataset.route));
    });
  }
};
