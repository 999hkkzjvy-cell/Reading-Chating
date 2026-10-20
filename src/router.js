import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { beginPageLoad } from './pageLoad.js';

const routes = {};
let afterRouteRender = () => {};

export function route(path, handler, opts = {}) {
  routes[path] = { handler, ...opts };
}

export function setAfterRouteRender(fn) {
  afterRouteRender = fn || (() => {});
}

function pathMatchesPrefix(path, prefix) {
  return path === prefix || path.startsWith(prefix + '/');
}

function isBanProtectedPath(path) {
  return ['/books', '/reading-circle', '/latin-america'].some(prefix => pathMatchesPrefix(path, prefix));
}

async function isCurrentUserBanned() {
  const user = store.get('user');
  if (!user || store.get('isAdmin')) return false;

  const cached = store.get('isBanned');
  if (typeof cached === 'boolean') return cached;

  const { data, error } = await sb.rpc('is_current_user_banned');
  if (error) {
    console.warn('Ban status unavailable:', error.message);
    return false;
  }
  store.set('isBanned', !!data);
  return !!data;
}

export const router = {
  navigate(path) {
    location.hash = '#' + path;
  },

  currentPath() {
    return location.hash.slice(1) || '/';
  },

  currentQuery() {
    const raw = location.hash.slice(1) || '/';
    const q = raw.indexOf('?');
    if (q === -1) return {};
    const params = {};
    new URLSearchParams(raw.slice(q + 1)).forEach((v, k) => { params[k] = v; });
    return params;
  },

  match(path) {
    // Strip query string for matching
    const cleanPath = path.replace(/\?.*$/, '');
    for (const [pattern, def] of Object.entries(routes)) {
      const keys = [];
      const regexStr = pattern.replace(/:(\w+)/g, (_, k) => {
        keys.push(k);
        return '([^/]+)';
      });
      const match = cleanPath.match(new RegExp('^' + regexStr + '$'));
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

  async render(load = beginPageLoad(this.currentPath())) {
    try {
      if (!load.isCurrent()) return;
      const path = this.currentPath();
      const cleanPath = path.replace(/\?.*$/, '');
      const matched = this.match(path);

      const authRequired = ['/member', '/profile', '/reading-circle', '/user', '/admin'].some(p => pathMatchesPrefix(cleanPath, p));
      if (authRequired && !store.get('user')) {
        if (pathMatchesPrefix(cleanPath, '/reading-circle') || pathMatchesPrefix(cleanPath, '/user')) {
          toast('会员登录方可浏览书友圈。', 'error');
        }
        load.cancel();
        return this.navigate('/login?redirect=' + encodeURIComponent(path));
      }

      if (pathMatchesPrefix(cleanPath, '/admin')) {
        const user = store.get('user');
        if (!user) {
          load.cancel();
          return this.navigate('/login?redirect=' + encodeURIComponent(path));
        }
        const { data: profile } = await sb.from('profiles').select('role').eq('id', user.id).single();
        if (!load.isCurrent()) return;
        if (profile?.role !== 'admin') {
          load.complete('<div class="container section"><div class="empty-state"><i data-lucide="shield-alert"></i><p>您没有管理权限</p></div></div>');
          if (typeof lucide !== 'undefined') lucide.createIcons();
          return;
        }
      }

      const banned = isBanProtectedPath(cleanPath) && await isCurrentUserBanned();
      if (!load.isCurrent()) return;
      if (banned) {
        load.complete(`
          <div class="container section">
            <div class="empty-state">
              <i data-lucide="shield-alert"></i>
              <p>该账号已被封禁，暂不能浏览共读书库、书友圈和西语文学板块。</p>
            </div>
          </div>
        `);
        if (typeof lucide !== 'undefined') lucide.createIcons();
        return;
      }

      if (matched) {
        const html = await matched.handler(matched.params);
        if (!load.complete(html)) return;
        window.scrollTo(0, 0);
      } else {
        if (!load.complete('<div class="container section"><div class="empty-state"><i data-lucide="file-question"></i><p>页面未找到</p></div></div>')) return;
      }

      afterRouteRender(path);
    } catch (err) {
      load.fail(err);
    }
  },

  updateNav(path) {
    const cleanPath = path.replace(/\?.*$/, '');
    document.querySelectorAll('#nav-links a').forEach(a => {
      const routePath = a.dataset.route;
      const isActive = routePath === '/'
        ? cleanPath === '/'
        : !!routePath && pathMatchesPrefix(cleanPath, routePath);
      a.classList.toggle('active', isActive);
    });
  }
};
