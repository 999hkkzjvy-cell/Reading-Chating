import { initPuzzleCaptcha, isCaptchaVerified, refreshCaptcha } from './captcha.js';
import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';
import { ACT_STATUSES, ACT_TYPES, GENRES, MOODS, STATUS_CLASS, STATUS_MAP } from './constants.js';
import {
  aiFillBookInfo,
  doCheckin,
  getCheckinDetail,
  getMonthCheckinsFull,
  getTodayCheckin,
  loadBooks,
  loadConfig,
  loadEvents,
  updateCheckin
} from './data.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { showModal, toast } from './ui.js';
import {
  esc,
  formatDate,
  formatDateTime,
  h,
  isDoubanBookUrl,
  parseHttpUrl,
  proxyImg,
  safeColor,
  safeMarked,
  safeUrl
} from './utils.js';

    // Calendar navigation state (lazy init)
    let calYear = null;
    let calMonth = null;
    let calCheckinsData = [];

    function ensureCalState() {
      if (calYear === null) {
        calYear = dayjs().year();
        calMonth = dayjs().month() + 1;
      }
    }

    // ===========================================
    // ROUTER
    // ===========================================
    const routes = {};
    function route(path, handler, opts = {}) { routes[path] = { handler, ...opts }; }

    const router = {
      navigate(path) { location.hash = '#' + path; },
      currentPath() { return location.hash.slice(1) || '/'; },
      match(path) {
        for (const [pattern, def] of Object.entries(routes)) {
          const keys = [];
          const regexStr = pattern.replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; });
          const match = path.match(new RegExp('^' + regexStr + '$'));
          if (match) {
            const params = {};
            keys.forEach((k, i) => params[k] = match[i + 1]);
            return { ...def, params };
          }
        }
        return null;
      },
      async render() {
        try {
        const path = this.currentPath();
        const matched = this.match(path);

        // Auth guard
        const authRequired = ['/profile', '/profile/edit', '/admin'].some(p => path.startsWith(p));
        if (authRequired && !store.get('user')) {
          return this.navigate('/login?redirect=' + encodeURIComponent(path));
        }

        // Admin guard — verify server-side via DB query (not just client store)
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
        } else {
          document.getElementById('view').innerHTML = '<div class="container section"><div class="empty-state"><i data-lucide="file-question"></i><p>页面未找到</p></div></div>';
        }
        lucide.createIcons();
        // Init puzzle captcha if present (login page)
        if (document.querySelector('.puzzle-box')) {
          setTimeout(() => initPuzzleCaptcha(), 150);
        }
        // Init Leaflet map if present
        if (document.getElementById('latam-leaflet-map')) {
          setTimeout(() => initLatamMap(), 50);
        }
        this.updateNav(path);
        bindGlobalEvents();
        } catch (err) {
          console.error('Router error:', err);
          const errText = String(err.message || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
          document.getElementById('view').innerHTML = '<div class="container section"><div class="empty-state"><i data-lucide="alert-triangle"></i><p>加载失败：' + errText + '</p><p style="font-size:0.85rem;color:var(--color-text-3);">请检查网络连接或刷新重试</p></div></div>';
          lucide.createIcons();
        }
      },
      updateNav(path) {
        document.querySelectorAll('#nav-links a').forEach(a => {
          a.classList.toggle('active', a.dataset.route && path.startsWith(a.dataset.route));
        });
      }
    };

    // ===========================================
    // EVENT BINDING (delegation for dynamic content)
    // ===========================================
    function bindGlobalEvents() {
      // Hamburger
      const hamburger = document.getElementById('hamburger-btn');
      const navLinks = document.getElementById('nav-links');
      if (hamburger && navLinks) {
        hamburger.onclick = () => navLinks.classList.toggle('open');
        navLinks.querySelectorAll('a').forEach(a => { a.onclick = () => navLinks.classList.remove('open'); });
      }
    }

    window.addEventListener('hashchange', () => router.render());
    window.addEventListener('load', async () => {
      bindGlobalEvents();
      await init();
      router.render();
      // Prefetch data in background — makes subsequent navigation instant
      loadBooks().catch(() => {});
      loadEvents().catch(() => {});
    });

    // Click delegation for internal links + captcha refresh
    document.addEventListener('click', (e) => {
      const link = e.target.closest('a[href^="#/"]');
      if (link) {
        e.preventDefault();
        const path = link.getAttribute('href').slice(1);
        router.navigate(path);
      }
      // Captcha refresh button
      if (e.target.closest('[data-action="captcha-refresh"]')) {
        refreshCaptcha();
      }
    });

    // ===========================================
    // AUTH HELPERS
    // ===========================================
    async function initAuth() {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        store.set('user', user);
        const { data: profile } = await sb.from('profiles').select('*').eq('id', user.id).single();
        store.set('profile', profile);
        store.set('isAdmin', profile?.role === 'admin');
      }
      renderNavUser();
    }

    // Rate limiting
    function checkLoginRateLimit() {
      const now = Date.now();
      const key = 'login_attempts';
      let record;
      try { record = JSON.parse(sessionStorage.getItem(key) || '{"count":0,"until":0}'); } catch(e) { record = { count: 0, until: 0 }; }
      if (record.until > now) return { blocked: true, remaining: Math.ceil((record.until - now) / 1000) };
      return { blocked: false, count: record.count };
    }
    function recordLoginAttempt(success) {
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

    async function signIn(email, password) {
      const { error } = await sb.auth.signInWithPassword({ email, password });
      if (error) throw error;
      await initAuth();
    }

    async function signUp(email, password, displayName) {
      const { error } = await sb.auth.signUp({
        email, password,
        options: { data: { display_name: displayName } }
      });
      if (error) throw error;
      toast('注册成功！请检查邮箱验证链接。');
    }

    async function signOut() {
      await sb.auth.signOut();
      store.set('user', null);
      store.set('profile', null);
      store.set('isAdmin', false);
      renderNavUser();
      router.navigate('/');
    }

    async function resetPassword(email) {
      const { error } = await sb.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.origin + window.location.pathname + '#/reset-password'
      });
      if (error) throw error;
      toast('密码重置邮件已发送，请检查邮箱。');
    }

    async function updatePassword(newPassword) {
      const { error } = await sb.auth.updateUser({ password: newPassword });
      if (error) throw error;
      toast('密码已重置，请重新登录。');
    }

    function renderNavUser() {
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

    // ===========================================
    // GENRE & STATUS HELPERS
    // ===========================================
    function statusTag(s) {
      return `<span class="tag ${STATUS_CLASS[s] || 'tag-upcoming'}">${STATUS_MAP[s] || h(s)}</span>`;
    }

    // ===========================================
    // CHECKIN UI HELPERS
    // ===========================================
    function showCheckinForm(existing = null) {
      const isEdit = !!existing;
      const dateStr = existing ? existing.checkin_date : dayjs().format('YYYY-MM-DD');
      const currentMood = existing?.mood_color || '';

      const html = `
        <form id="checkin-form">
          <div class="form-group">
            <label>签到日期</label>
            <input type="date" value="${esc(dateStr)}" readonly disabled style="opacity:0.7;cursor:not-allowed;">
            <input type="hidden" name="checkin_date" value="${esc(dateStr)}">
          </div>
          <div class="form-group">
            <label>正在读的书 *</label>
            <input type="text" name="book_title" value="${esc(existing?.book_title || '')}" placeholder="例如：《红楼梦》" required>
          </div>
          <div class="form-group">
            <label>摘抄</label>
            <textarea name="excerpt" placeholder="今天读到的触动你的句子...">${h(existing?.excerpt || '')}</textarea>
          </div>
          <div class="form-group">
            <label>感想</label>
            <textarea name="reflection" placeholder="今天的阅读感悟...">${h(existing?.reflection || '')}</textarea>
          </div>
          <div class="form-group">
            <label>心情颜色</label>
            <div class="mood-swatches">
              ${MOODS.map(m => {
                const isSelected = m.value === currentMood || (!m.value && !currentMood);
                const selectedClass = isSelected ? ' selected' : '';
                const style = m.value ? `background:${m.value};` : '';
                return `<div class="mood-swatch ${m.cls || ''}${selectedClass}"
                  data-color="${m.value}" style="${style}"
                  title="${m.label}"></div>`;
              }).join('')}
            </div>
            <input type="hidden" name="mood_color" value="${esc(currentMood)}" id="mood-color-input">
          </div>
          <button type="submit" class="btn btn-primary" style="width:100%">
            ${isEdit ? '保存修改' : '签到'}
          </button>
          ${isEdit ? '<input type="hidden" name="is_edit" value="1">' : ''}
        </form>`;

      const modal = showModal(isEdit ? '编辑签到' : '每日阅读签到', html);
      modal.querySelectorAll('.mood-swatch').forEach(swatch => {
        swatch.addEventListener('click', () => {
          modal.querySelectorAll('.mood-swatch').forEach(s => s.classList.remove('selected'));
          swatch.classList.add('selected');
          modal.querySelector('#mood-color-input').value = swatch.dataset.color;
        });
      });
      return modal;
    }

    function showCheckinDetail(checkin) {
      const moodColor = safeColor(checkin.mood_color);
      const bookTitle = checkin.book_title || '未记录';
      const html = `
        <div class="checkin-detail-head">
          <span class="mood-dot" style="background:${moodColor};${!checkin.mood_color ? 'border-style:dashed;' : ''}"></span>
          <strong style="font-size:1.1rem;">${formatDate(checkin.checkin_date)}</strong>
        </div>
        <div class="checkin-detail-book">
          <span style="color:var(--color-text-3);">在读：</span>
          <strong>${h(bookTitle)}</strong>
        </div>
        ${checkin.excerpt ? `
          <div style="margin-bottom:var(--space-2);">
            <div style="color:var(--color-text-3);font-size:0.82rem;font-weight:600;margin-bottom:6px;">摘抄</div>
            <div class="checkin-excerpt"><blockquote>${checkin.excerpt.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</blockquote></div>
          </div>
        ` : ''}
        ${checkin.reflection ? `
          <div style="margin-bottom:var(--space-2);">
            <div style="color:var(--color-text-3);font-size:0.82rem;font-weight:600;margin-bottom:6px;">感想</div>
            <div class="checkin-reflection"><p>${checkin.reflection.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</p></div>
          </div>
        ` : ''}
        <div style="text-align:right;margin-top:var(--space-3);">
          <button class="btn btn-outline btn-sm" id="edit-checkin-btn" data-date="${esc(checkin.checkin_date)}">编辑</button>
        </div>
      `;
      showModal('签到详情', html);
    }

    async function refreshCalendar() {
      ensureCalState();
      calCheckinsData = await getMonthCheckinsFull(calYear, calMonth);
      const now = dayjs();
      const todayStr = now.format('YYYY-MM-DD');
      const map = new Map(calCheckinsData.map(c => [c.checkin_date, c]));

      const gridEl = document.getElementById('cal-grid');
      if (!gridEl) return;

      const firstDay = dayjs(`${calYear}-${String(calMonth).padStart(2,'0')}-01`);
      const daysInMonth = firstDay.daysInMonth();
      const startDayOfWeek = firstDay.day();
      const prevMonthDays = firstDay.subtract(1, 'day').daysInMonth();

      let cells = '';
      ['日','一','二','三','四','五','六'].forEach(d => { cells += `<div class="day-name">${d}</div>`; });
      for (let i = startDayOfWeek - 1; i >= 0; i--) {
        cells += `<div class="day other-month">${prevMonthDays - i}</div>`;
      }
      for (let d = 1; d <= daysInMonth; d++) {
        const dateStr = firstDay.date(d).format('YYYY-MM-DD');
        const checkin = map.get(dateStr);
        let cls = 'day';
        if (checkin) {
          cls += ' checked';
        } else if (dateStr === todayStr) cls += ' today';
        else if (dayjs(dateStr).isAfter(now, 'day')) cls += ' future';
        const style = (checkin && checkin.mood_color)
          ? `style="--mood-dot:${safeColor(checkin.mood_color, '#c17d4b')}"` : '';
        const dataDate = checkin ? `data-date="${esc(dateStr)}"` : '';
        cells += `<div class="${cls}" ${style} ${dataDate}><span>${d}</span></div>`;
      }
      const totalCells = startDayOfWeek + daysInMonth;
      const remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
      for (let d = 1; d <= remaining; d++) {
        cells += `<div class="day other-month"><span>${d}</span></div>`;
      }
      gridEl.innerHTML = cells;

      const label = document.getElementById('cal-month-label');
      if (label) label.textContent = `${calYear}年${calMonth}月`;

      // Update checkin button text
      const btn = document.getElementById('checkin-btn');
      if (btn) {
        const todayCheckin = calCheckinsData.find(c => c.checkin_date === todayStr);
        btn.textContent = todayCheckin ? '编辑今日签到' : '📖 今日签到';
        btn.classList.toggle('btn-ghost', !!todayCheckin);
      }
    }

    // ===========================================
    // COMPONENT: Book Card
    // ===========================================
    function renderBookCard(b, opts = {}) {
      const { showDesc = false, descLen = 150, link = true } = opts;
      const authorLine = b.author_country ? `[${h(b.author_country)}] ${h(b.author)} 著` : `${h(b.author)} 著`;
      const inner = `
        <div class="cover">
          ${b.cover_url ? `<img src="${safeUrl(b.cover_url)}" alt="">` : '<i data-lucide="book"></i>'}
          <span class="status-badge tag ${STATUS_CLASS[b.status] || 'tag-upcoming'}">${STATUS_MAP[b.status] || h(b.status)}</span>
        </div>
        <div class="card-body">
          <h3>${h(b.title)}</h3>
          <div class="book-meta">${authorLine}</div>
          <div class="meta"><span class="tag tag-genre">${h(b.genre || '文学')}</span></div>
        </div>`;
      return link
        ? `<a href="#/books/${b.id}" class="card book-card card-clickable" style="color:inherit;">${inner}</a>`
        : `<div class="card book-card">${inner}</div>`;
    }

    function renderHomeBookCard(b) {
      const authorLine = [b.author_country ? `[${h(b.author_country)}]` : '', h(b.author)].filter(Boolean).join(' ') + ' 著';
      return `
        <div class="current-book-card">
          <span class="status-badge tag ${STATUS_CLASS[b.status] || 'tag-upcoming'}">${STATUS_MAP[b.status] || h(b.status)}</span>
          <div class="cover-slot">
            ${b.cover_url ? `<img src="${safeUrl(b.cover_url)}" alt="">` : '<i data-lucide="book"></i>'}
          </div>
          <div class="info">
            <h3>${h(b.title)}</h3>
            <div class="book-meta">${authorLine}</div>
            <div class="book-meta${b.translator ? '' : ' muted'}">${b.translator ? h(b.translator) + ' 译' : '不限译本'}</div>
            <div class="book-meta${b.publisher ? '' : ' muted'}">${h(b.publisher) || '不限版本'}</div>
            ${b.start_date && b.end_date ? `<div class="period"><i data-lucide="calendar" style="width:14px;height:14px;display:inline;vertical-align:-2px;"></i> ${formatDate(b.start_date)} — ${formatDate(b.end_date)}</div>` : ''}
            <p style="font-size:0.9rem;color:var(--color-text-2);margin-bottom:12px;">${b.description ? h(b.description.slice(0, 150)) + '...' : ''}</p>
            <a href="#/books/${b.id}" class="btn btn-primary btn-sm">查看共读详情</a>
          </div>
        </div>`;
    }

    // ===========================================
    // ROUTE: LOGIN / REGISTER
    // ===========================================
    route('/login', (params) => {
      const redirect = location.hash.includes('redirect=') ? decodeURIComponent(location.hash.split('redirect=')[1]) : '/';
      return `
        <div class="container auth-page">
          <div class="card">
            <h2>登录</h2>
            <form id="login-form" autocomplete="off">
              <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
              <div class="form-group"><label>密码</label><input type="password" name="password" required minlength="6"></div>
              <div class="captcha-row">
                <div class="puzzle-box">
                  <div class="pz-bg"></div>
                  <div class="pz-gap"></div>
                  <div class="pz-piece"></div>
                  <div class="pz-status">拖动滑块使拼图对齐缺口</div>
                </div>
                <div class="puzzle-slider">
                  <div class="pz-track"></div>
                  <div class="pz-handle"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg></div>
                </div>
                <button type="button" class="captcha-refresh" data-action="captcha-refresh">🔄 换一张</button>
              </div>
              <div style="display:flex;gap:var(--space-2);">
                <button type="submit" class="btn btn-primary" style="flex:1">登录</button>
                <a href="#/register" class="btn btn-primary" style="flex:1;text-align:center;">注册</a>
              </div>
              <div style="text-align:center;margin-top:var(--space-2);">
                <a href="#/forgot-password" style="font-size:0.9rem;color:var(--color-text-2);">忘记密码？</a>
              </div>
            </form>
            <div id="login-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          </div>
        </div>
      `;
    });

    route('/register', () => {
      return `
        <div class="container auth-page">
          <div class="card">
            <h2>注册</h2>
            <form id="register-form">
              <div class="form-group"><label>显示名称</label><input type="text" name="displayName" required></div>
              <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
              <div class="form-group"><label>密码（至少6位）</label><input type="password" name="password" required minlength="6"></div>
              <button type="submit" class="btn btn-primary" style="width:100%">注册</button>
            </form>
            <div class="alt-link">已有账号？<a href="#/login">去登录</a></div>
            <div id="reg-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          </div>
        </div>
      `;
    });

    // === Forgot Password ===
    route('/forgot-password', () => {
      return `
        <div class="container auth-page">
          <div class="card">
            <h2>忘记密码</h2>
            <p style="text-align:center;color:var(--color-text-2);font-size:0.9rem;margin-bottom:var(--space-3);">
              输入注册邮箱，我们将发送重置密码链接。
            </p>
            <form id="forgot-form">
              <div class="form-group"><label>邮箱</label><input type="email" name="email" required></div>
              <button type="submit" class="btn btn-primary" style="width:100%">发送重置邮件</button>
            </form>
            <div class="alt-link"><a href="#/login">← 返回登录</a></div>
            <div id="forgot-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
            <div id="forgot-msg" style="color:var(--color-success);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          </div>
        </div>
      `;
    });

    // === Reset Password (callback from email) ===
    route('/reset-password', () => {
      return `
        <div class="container auth-page">
          <div class="card">
            <h2>重置密码</h2>
            <p style="text-align:center;color:var(--color-text-2);font-size:0.9rem;margin-bottom:var(--space-3);">
              请输入你的新密码。
            </p>
            <form id="reset-form">
              <div class="form-group"><label>新密码（至少6位）</label><input type="password" name="password" required minlength="6"></div>
              <button type="submit" class="btn btn-primary" style="width:100%">重置密码</button>
            </form>
            <div class="alt-link"><a href="#/login">← 返回登录</a></div>
            <div id="reset-error" style="color:var(--color-danger);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
            <div id="reset-msg" style="color:var(--color-success);text-align:center;margin-top:12px;font-size:0.9rem;"></div>
          </div>
        </div>
      `;
    });

    // Bind login/register/forgot/reset form events
    document.addEventListener('submit', async (e) => {
      if (e.target.id === 'login-form') {
        e.preventDefault();
        // Rate limit check
        const limit = checkLoginRateLimit();
        if (limit.blocked) {
          document.getElementById('login-error').textContent = `登录尝试次数过多，请 ${limit.remaining} 秒后重试。`;
          return;
        }
        // Captcha validation
        if (!isCaptchaVerified()) {
          document.getElementById('login-error').textContent = '请完成滑动验证。';
          return;
        }
        const fd = new FormData(e.target);
        try {
          await signIn(fd.get('email'), fd.get('password'));
          recordLoginAttempt(true);
          const redirect = location.hash.includes('redirect=') ? decodeURIComponent(location.hash.split('redirect=')[1]) : '/';
          router.navigate(redirect);
        } catch (err) {
          recordLoginAttempt(false);
          refreshCaptcha();
          document.getElementById('login-error').textContent = err.message;
        }
      }
      if (e.target.id === 'register-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        try {
          await signUp(fd.get('email'), fd.get('password'), fd.get('displayName'));
          router.navigate('/login');
        } catch (err) {
          document.getElementById('reg-error').textContent = err.message;
        }
      }
      if (e.target.id === 'forgot-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        const btn = e.target.querySelector('button[type="submit"]');
        btn.disabled = true; btn.textContent = '发送中...';
        try {
          await resetPassword(fd.get('email'));
          document.getElementById('forgot-msg').textContent = '密码重置邮件已发送，请检查邮箱。如果未收到，请查看垃圾邮件。';
          document.getElementById('forgot-error').textContent = '';
        } catch (err) {
          document.getElementById('forgot-error').textContent = err.message;
          document.getElementById('forgot-msg').textContent = '';
        } finally {
          btn.disabled = false; btn.textContent = '发送重置邮件';
        }
      }
      if (e.target.id === 'reset-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        const btn = e.target.querySelector('button[type="submit"]');
        btn.disabled = true; btn.textContent = '重置中...';
        try {
          await updatePassword(fd.get('password'));
          document.getElementById('reset-msg').textContent = '密码已重置，即将跳转登录页...';
          document.getElementById('reset-error').textContent = '';
          setTimeout(() => router.navigate('/login'), 1500);
        } catch (err) {
          document.getElementById('reset-error').textContent = err.message;
          document.getElementById('reset-msg').textContent = '';
        } finally {
          btn.disabled = false; btn.textContent = '重置密码';
        }
      }
    });

    // ===========================================
    // ROUTE: HOME
    // ===========================================
    route('/', async () => {
      const config = await loadConfig();
      const books = await loadBooks();
      // Show the two books with most recent end dates
      const latestBooks = [...books]
        .filter(b => b.end_date)
        .sort((a, b) => dayjs(b.end_date).diff(dayjs(a.end_date)))
        .slice(0, 2);
      if (latestBooks.length === 0 && books.length > 0) {
        latestBooks.push(...books.slice(0, 2 - latestBooks.length));
      }

      const rulesHtml = safeMarked(config.group_rules || '群规加载中...');

      // Intro: preserve user's line breaks, strip markdown per line
      const introLines = config.reading_plan_intro
        ? config.reading_plan_intro
            .split(/\n\r?/)
            .map(line => line.replace(/[#*>\-\[\]()\`_~]/g, '').trim())
            .filter(line => line)
            .join('<br>')
        : '用阅读抵御孤独，遇见同频的书友。<br>有深度、有温度的线上共读社群。';

      const bookCardsHtml = latestBooks.length > 0
        ? `<div class="current-book-section" style="display:flex;gap:1cm;justify-content:center;flex-wrap:wrap;">${latestBooks.map(renderHomeBookCard).join('')}</div>`
        : '';

      return `
        <section class="hero">
          <div class="container">
            <h1>以读攻独</h1>
            <div class="hero-divider"></div>
            <p class="lead">${introLines}</p>
          </div>
        </section>
        ${bookCardsHtml}
        <section class="section">
          <div class="container">
            <h2 style="margin-bottom:var(--space-3);">📋 群规</h2>
            <div class="card"><div class="card-body md-content" style="max-width:none;">${rulesHtml}</div></div>
          </div>
        </section>
        <section class="section" style="background:var(--color-bg-alt);">
          <div class="container" style="text-align:center;">
            <h2 style="margin-bottom:var(--space-2);">加入我们</h2>
            <p style="color:var(--color-text-2);margin-bottom:var(--space-3);">注册账号即可参与每日阅读签到，记录你的阅读旅程。</p>
            ${store.get('user') ? '' : '<a href="#/register" class="btn btn-primary btn-lg">立即注册</a>'}
          </div>
        </section>
      `;
    });

    // ===========================================
    // ROUTE: BOOKS LIST
    // ===========================================
    route('/books', async () => {
      const books = await loadBooks();
      let activeGenre = '全部';
      let activeStatus = '全部';

      // Build genre & status counts
      const genreSet = new Set(books.map(b => b.genre));
      const statusCounts = { upcoming: 0, active: 0, completed: 0 };
      books.forEach(b => { if (statusCounts[b.status] !== undefined) statusCounts[b.status]++; });

      function renderList(genreFilter, statusFilter) {
        let filtered = books;
        if (genreFilter !== '全部') filtered = filtered.filter(b => b.genre === genreFilter);
        if (statusFilter !== '全部') filtered = filtered.filter(b => b.status === statusFilter);
        if (filtered.length === 0) {
          return '<div class="empty-state"><i data-lucide="book"></i><p>暂无书籍</p></div>';
        }
        return `<div class="grid-6">${filtered.map(b => renderBookCard(b)).join('')}</div>`;
      }

      // We use query strings for filters. For simplicity, store filter state on the books view.
      return `
        <div class="container section" id="books-page">
          <div class="page-header"><h1>共读书库</h1><div class="subtitle">共 ${books.length} 本书</div></div>
          <div style="display:flex;flex-wrap:wrap;gap:var(--space-4);margin-bottom:var(--space-3);">
            <div>
              <div style="font-size:0.85rem;color:var(--color-text-3);margin-bottom:4px;">类型</div>
              <div class="filters" id="genre-filters">
                ${GENRES.filter(g => g === '全部' || genreSet.has(g)).map(g => `<button class="filter-chip${g === '全部' ? ' active' : ''}" data-genre="${g}">${g}</button>`).join('')}
              </div>
            </div>
            <div>
              <div style="font-size:0.85rem;color:var(--color-text-3);margin-bottom:4px;">状态</div>
              <div class="filters" id="status-filters">
                <button class="filter-chip active" data-status="全部">全部</button>
                <button class="filter-chip" data-status="upcoming">即将开读</button>
                <button class="filter-chip" data-status="active">正在共读</button>
                <button class="filter-chip" data-status="completed">已读完</button>
              </div>
            </div>
          </div>
          <div id="books-grid">${renderList('全部', '全部')}</div>
        </div>
      `;
    });

    // Book list filter interactions
    document.addEventListener('click', (e) => {
      const chip = e.target.closest('#genre-filters .filter-chip, #status-filters .filter-chip');
      if (!chip) return;
      const container = chip.closest('.filters');
      container.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      const genre = document.querySelector('#genre-filters .filter-chip.active')?.dataset.genre || '全部';
      const status = document.querySelector('#status-filters .filter-chip.active')?.dataset.status || '全部';
      const grid = document.getElementById('books-grid');
      if (grid) {
        const books = store.get('books');
        let filtered = books;
        if (genre !== '全部') filtered = filtered.filter(b => b.genre === genre);
        if (status !== '全部') filtered = filtered.filter(b => b.status === status);
        if (filtered.length === 0) {
          grid.innerHTML = '<div class="empty-state"><i data-lucide="book"></i><p>暂无匹配书籍</p></div>';
        } else {
          grid.innerHTML = `<div class="grid-6">${filtered.map(b => renderBookCard(b)).join('')}</div>`;
        }
        lucide.createIcons();
      }
    });

    // ===========================================
    // ROUTE: BOOK DETAIL (v2)
    // ===========================================
    route('/books/:id', async (params) => {
      // Check memory cache first (hit if user visited book list before)
      let book = store.get('books').find(b => b.id == params.id);
      if (!book) {
        const { data } = await sb.from('books').select('*').eq('id', params.id).single();
        book = data;
      }
      if (!book) return '<div class="container section"><div class="empty-state"><i data-lucide="book"></i><p>书籍未找到</p></div></div>';

      // Tab 1: 简介 — description + author_bio + historical_context
      const descHtml = safeMarked(book.description || '暂无简介。');
      const authorBioHtml = safeMarked(book.author_bio || '暂无作者简介。');
      const contextHtml = safeMarked(book.historical_context || '暂无时代背景介绍。');
      const introHtml = `
        <div class="md-content" style="max-width:none;">
          <h2>书籍简介</h2>
          <hr style="border:none;border-top:1px solid var(--color-border);margin:6px 0 var(--space-2);">
          ${descHtml}
          <div style="height:var(--space-3);"></div>
          <h2>作者简介</h2>
          <hr style="border:none;border-top:1px solid var(--color-border);margin:6px 0 var(--space-2);">
          ${authorBioHtml}
          <div style="height:var(--space-3);"></div>
          <h2>创作时代背景</h2>
          <hr style="border:none;border-top:1px solid var(--color-border);margin:6px 0 var(--space-2);">
          ${contextHtml}
        </div>`;

      // Tab 2: 领读人简介 — host + host_intro
      const hostIntroHtml = safeMarked(book.host_intro || '暂无领读人信息。');
      const hostTabHtml = `
        <div class="md-content" style="max-width:none;">
          <h2>领读人：${h(book.host || '待定')}</h2>
          <hr style="border:none;border-top:1px solid var(--color-border);margin:var(--space-2) 0;">
          <div style="font-size:1rem;line-height:1.8;">${hostIntroHtml}</div>
        </div>`;

      // Tab 2.5: 灵沁碎碎念 — host_notes (only if has content)
      const hostNotesHtml = book.host_notes ? safeMarked(book.host_notes) : '';
      const hostNotesTabHtml = book.host_notes ? `
        <div class="md-content" style="max-width:none;">
          ${hostNotesHtml}
        </div>` : '';
      const hostNotesTabBtn = book.host_notes ? '<button class="tab" data-tab="hostnotes">灵沁碎碎念</button>' : '';
      const hostNotesTabContent = book.host_notes ? `<div id="tab-hostnotes" class="tab-content" style="display:none;">${hostNotesTabHtml}</div>` : '';

      // Tab 3: 版本建议 — edition_notes + structured cards
      let editions = [];
      try { editions = typeof book.edition_guide === 'string' ? JSON.parse(book.edition_guide||'[]') : (book.edition_guide||[]); } catch(e){}
      const editionNotesHtml = safeMarked(book.edition_notes || '');
      const editionsCardsHtml = editions.length === 0 ? '<p style="color:var(--color-text-3);">暂无版本建议。</p>' : `
        <div style="display:flex;flex-direction:column;gap:var(--space-2);">
          ${editions.map(e => `
            <div class="edition-card">
              <h3>${h(e.name || '未命名版本')}</h3>
              <div class="edition-meta">
                ${e.translator ? `<div>译本：${h(e.translator)} 译</div>` : ''}
                ${e.publisher ? `<div>出版方：${h(e.publisher)}</div>` : ''}
              </div>
              <div class="edition-pros-cons">
                ${e.pros ? `<div><span class="pros-label">优点</span><p>${h(e.pros)}</p></div>` : ''}
                ${e.cons ? `<div><span class="cons-label">缺点</span><p>${h(e.cons)}</p></div>` : ''}
              </div>
              <div class="edition-links">
                ${e.buy_link ? `<a href="${safeUrl(e.buy_link)}" target="_blank" class="btn btn-outline btn-sm">购买</a>` : ''}
                ${e.douban_link ? `<a href="${safeUrl(e.douban_link)}" target="_blank" class="btn btn-outline btn-sm">豆瓣</a>` : ''}
              </div>
            </div>
          `).join('')}
        </div>`;
      const editionsHtml = `
        ${book.edition_notes ? `<div class="md-content" style="max-width:none;margin-bottom:var(--space-4);">${editionNotesHtml}</div>` : ''}
        ${editionsCardsHtml}`;

      // Tab 4: 时间计划
      let scheduleData = { summary: '', pdf_url: '' };
      try { scheduleData = typeof book.reading_schedule === 'string' ? JSON.parse(book.reading_schedule || '{}') : (book.reading_schedule || {}); } catch(e){}
      const scheduleSummaryHtml = safeMarked(scheduleData.summary || '暂无时间安排。');
      const scheduleHtml = `
        <div class="md-content" style="max-width:none;">
          ${scheduleSummaryHtml}
          ${scheduleData.pdf_url ? `<div style="margin-top:var(--space-4);padding-top:var(--space-3);border-top:1px solid var(--color-border);">
            <a href="${safeUrl(scheduleData.pdf_url)}" target="_blank" class="btn btn-outline btn-sm"><i data-lucide="file-text"></i> 下载时间计划 PDF</a>
          </div>` : ''}
        </div>`;

      // Tab 5: 活动安排 — unified activities
      let activities = [];
      try { activities = typeof book.activities === 'string' ? JSON.parse(book.activities||'[]') : (book.activities||[]); } catch(e){}
      const STATUS_TAG_CLASS = { '计划中': 'tag-upcoming', '进行中': 'tag-active', '已完结': 'tag-completed' };
      const ACT_TYPE_CLASS = { '导读预热':'tag-act-导读预热','精读分析':'tag-act-精读分析','文艺放映':'tag-act-文艺放映','嘉宾分享':'tag-act-嘉宾分享','圆桌讨论':'tag-act-圆桌讨论','线下活动':'tag-act-线下活动','签售征订':'tag-act-签售征订','其他':'tag-act-其他' };
      const activitiesHtml = activities.length === 0 ? '<p style="color:var(--color-text-3);">暂无活动安排。</p>' : `
        <div style="display:flex;flex-direction:column;gap:var(--space-2);">
          ${activities.map(a => `
            <div class="card" style="padding:var(--space-2) var(--space-3);">
              <div style="display:flex;align-items:center;gap:var(--space-1);flex-wrap:wrap;margin-bottom:6px;">
                <span class="tag ${ACT_TYPE_CLASS[a.type] || 'tag-genre'}">${h(a.type || '活动')}</span>
                <span class="tag ${STATUS_TAG_CLASS[a.status] || 'tag-upcoming'}">${h(a.status || '')}</span>
                <strong>${h(a.title)}</strong>
              </div>
              ${a.time ? `<div style="font-size:0.85rem;color:var(--color-text-2);margin-bottom:4px;">📅 ${h(a.time)}</div>` : ''}
              ${a.guests ? `<div style="font-size:0.85rem;color:var(--color-text-2);margin-bottom:4px;">👤 ${h(a.guests)}</div>` : ''}
              ${a.description ? `<div style="font-size:0.9rem;color:var(--color-text-2);margin-bottom:6px;">${h(a.description)}</div>` : ''}
              <div style="display:flex;gap:var(--space-1);flex-wrap:wrap;align-items:center;">
                ${a.meeting_link ? `<a href="${safeUrl(a.meeting_link)}" target="_blank" class="btn btn-outline btn-sm">活动链接</a>` : ''}
                ${a.replay_link ? `<a href="${safeUrl(a.replay_link)}" target="_blank" class="btn btn-outline btn-sm">回放回顾</a>` : ''}
                ${!a.meeting_link && !a.replay_link && a.status === '计划中' ? '<span style="font-size:0.82rem;color:var(--color-text-3);">积极筹备中，敬请期待</span>' : ''}
              </div>
            </div>
          `).join('')}
        </div>`;

      // Tab 6: 资源材料
      let resources = { extended_reading: [], text_materials: [], film_resources: [], other: [] };
      try { resources = typeof book.resources === 'string' ? JSON.parse(book.resources) : (book.resources || {}); } catch(e) {}

      // Fetch Douban metadata for extended reading items with Douban URLs
      const extItems = resources.extended_reading || [];
      const doubanCache = {};
      const doubanUrls = extItems.filter(item => isDoubanBookUrl(item.url)).map(item => item.url);
      if (doubanUrls.length > 0) {
        // Check cache first
        try {
          const { data: cached } = await sb.from('douban_book_cache').select('*').in('douban_url', doubanUrls);
          if (cached) cached.forEach(c => { doubanCache[c.douban_url] = c; });
        } catch(e) {}
        // Fetch uncached ones via Edge Function
        const uncached = doubanUrls.filter(url => !doubanCache[url]);
        if (uncached.length > 0) {
          const results = await Promise.allSettled(uncached.map(url =>
            fetch(`${SUPABASE_URL}/functions/v1/fetch-douban-book`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${SUPABASE_ANON_KEY}` },
              body: JSON.stringify({ url })
            }).then(r => r.json()).then(r => (r && r.success) ? r.data : null).catch(() => null)
          ));
          results.forEach((r, i) => {
            if (r.status === 'fulfilled' && r.value) {
              doubanCache[uncached[i]] = r.value;
            }
          });
        }
      }

      // Render extended reading as cards with Douban metadata
      const extReadingHtml = extItems.length === 0 ? '' : `
        <div style="margin-bottom:var(--space-3);">
          <h4 style="margin-bottom:var(--space-1);">延伸读物</h4>
          <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:var(--space-2);">
            ${extItems.map(item => {
              const db = doubanCache[item.url] || {};
              return `
              <div class="new-book-card">
                <a href="${safeUrl(item.url)}" target="_blank" rel="noopener" class="nb-cover" style="width:100px;">
                  ${db.cover_url
                    ? `<img src="${esc(proxyImg(db.cover_url))}" alt="" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='block';">`
                    : ''}
                  <i data-lucide="book" class="cover-fallback" style="${db.cover_url ? 'display:none;' : ''}"></i>
                </a>
                <div class="nb-body">
                  <h3><a href="${safeUrl(item.url)}" target="_blank" rel="noopener">${h(db.title || item.title)}</a></h3>
                  ${db.author ? `<div class="nb-row"><span class="nb-label">作者</span>${h(db.author)}</div>` : ''}
                  ${db.publisher ? `<div class="nb-row"><span class="nb-label">出版方</span>${h(db.publisher)}</div>` : ''}
                  ${db.rating ? `<div class="nb-row rating">⭐${h(db.rating)} · ${db.review_count || 0}人评价</div>` : ''}
                  ${item.description ? `<div class="nb-row" style="white-space:normal;margin-top:2px;">${h(item.description)}</div>` : ''}
                  <div class="nb-actions" style="margin-top:4px;">
                    <a href="${safeUrl(item.url)}" target="_blank" rel="noopener" class="btn btn-outline btn-sm">豆瓣详情</a>
                  </div>
                </div>
              </div>`;
            }).join('')}
          </div>
        </div>`;

      // Render other resource sections as simple lists
      const otherSections = [
        { key: 'text_materials', label: '文字材料' },
        { key: 'film_resources', label: '影视资源' },
        { key: 'other', label: '其他' }
      ];
      const resourcesHtml = extReadingHtml + otherSections.map(sec => {
        const items = resources[sec.key] || [];
        if (items.length === 0) return '';
        return `<div style="margin-bottom:var(--space-3);">
          <h4 style="margin-bottom:var(--space-1);">${sec.label}</h4>
          <div style="display:flex;flex-direction:column;gap:4px;">
            ${items.map(item => `
              <div style="padding:6px 0;border-bottom:1px solid var(--color-border);display:flex;justify-content:space-between;align-items:center;gap:var(--space-2);">
                <span>${h(item.title)}</span>
                ${item.url ? `<a href="${safeUrl(item.url)}" target="_blank" style="font-size:0.85rem;flex-shrink:0;">查看</a>` : ''}
              </div>
            `).join('')}
          </div>
        </div>`;
      }).join('');

      // Tab 7: 聊天干货
      let chats = [];
      try { chats = typeof book.chatsubstance === 'string' ? JSON.parse(book.chatsubstance||'[]') : (book.chatsubstance||[]); } catch(e){}
      const chatsHtml = chats.length === 0 ? '<p style="color:var(--color-text-3);">暂无聊天干货。</p>' : `
        <div style="display:flex;flex-direction:column;gap:var(--space-3);">
          ${chats.map(c => `
            <div class="edition-card">
              <h3 style="margin-bottom:var(--space-1);">${c.topic || '干货主题'}</h3>
              <div style="font-size:0.88rem;color:var(--color-text-2);margin-bottom:var(--space-2);">主发言人：${c.speaker || '未知'}</div>
              ${c.content ? `<div class="md-content" style="max-width:none;font-size:0.95rem;">${safeMarked(c.content)}</div>` : ''}
            </div>
          `).join('')}
        </div>`;

      return `
        <div class="container section">
          <a href="#/books" style="font-size:0.9rem;color:var(--color-text-2);margin-bottom:var(--space-3);display:inline-block;">← 返回共读书库</a>
          <div style="display:flex;gap:var(--space-4);flex-wrap:wrap;">
            <div style="width:180px;flex-shrink:0;">
              <div style="aspect-ratio:3/4;border-radius:var(--radius-md);background:var(--color-bg-alt);overflow:hidden;display:flex;align-items:center;justify-content:center;font-family:var(--font-serif);font-size:2rem;color:var(--color-text-3);">
                ${book.cover_url ? `<img src="${safeUrl(book.cover_url)}" alt="" style="width:100%;height:100%;object-fit:cover;">` : '<i data-lucide="book"></i>'}
              </div>
            </div>
            <div style="flex:1;min-width:280px;">
              ${statusTag(book.status)}
              <h1 style="margin-top:var(--space-1);">${h(book.title)}</h1>
              <div style="color:var(--color-text-2);font-size:1.05rem;margin:var(--space-1) 0;">
                ${h(book.author)} 著${book.translator ? ' · ' + h(book.translator) + ' 译' : ''}
              </div>
              ${book.publisher ? `<div style="color:var(--color-text-3);font-size:0.9rem;">${h(book.publisher)}</div>` : ''}
              ${book.start_date && book.end_date ? `<div style="color:var(--color-text-3);font-size:0.9rem;margin-top:4px;">共读期：${formatDate(book.start_date)} — ${formatDate(book.end_date)}</div>` : ''}
            </div>
          </div>

          <div class="tabs" id="book-tabs" style="margin-top:var(--space-5);">
            <button class="tab active" data-tab="intro">简介</button>
            <button class="tab" data-tab="host">领读人简介</button>
            ${hostNotesTabBtn}
            <button class="tab" data-tab="edition">版本建议</button>
            <button class="tab" data-tab="schedule">时间计划</button>
            <button class="tab" data-tab="activities">活动安排</button>
            <button class="tab" data-tab="resources">资源材料</button>
            <button class="tab" data-tab="chats">聊天干货</button>
          </div>

          <div id="tab-intro" class="tab-content">${introHtml}</div>
          <div id="tab-host" class="tab-content" style="display:none;">${hostTabHtml}</div>
          ${hostNotesTabContent}
          <div id="tab-edition" class="tab-content" style="display:none;">${editionsHtml}</div>
          <div id="tab-schedule" class="tab-content" style="display:none;">${scheduleHtml}</div>
          <div id="tab-activities" class="tab-content" style="display:none;">${activitiesHtml}</div>
          <div id="tab-resources" class="tab-content" style="display:none;">
            ${resourcesHtml || '<p style="color:var(--color-text-3);">暂无资源材料。</p>'}
          </div>
          <div id="tab-chats" class="tab-content" style="display:none;">
            ${chatsHtml}
          </div>
        </div>
      `;
    });

    // Tab switching
    document.addEventListener('click', (e) => {
      const tab = e.target.closest('#book-tabs .tab');
      if (!tab) return;
      document.querySelectorAll('#book-tabs .tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      document.querySelectorAll('.tab-content').forEach(c => c.style.display = 'none');
      const target = document.getElementById('tab-' + tab.dataset.tab);
      if (target) target.style.display = '';
    });

    // ===========================================
    // ROUTE: EVENTS LIST
    // ===========================================
    route('/events', async () => {
      const events = await loadEvents();
      if (events.length === 0) {
        return `<div class="container section"><div class="page-header"><h1>线下活动</h1></div><div class="empty-state"><i data-lucide="calendar"></i><p>暂无线下活动</p></div></div>`;
      }
      return `
        <div class="container section">
          <div class="page-header"><h1>线下活动</h1><div class="subtitle">推荐线下活动</div></div>
          <div class="grid-3">
            ${events.map(ev => `
              <a href="#/events/${ev.id}" class="card event-card card-clickable" style="color:inherit;">
                <div class="poster">
                  ${ev.poster_url ? `<img src="${safeUrl(ev.poster_url)}" alt="">` : '<i data-lucide="image" style="width:36px;height:36px;"></i>'}
                </div>
                <div class="card-body">
                  <span class="tag ${STATUS_CLASS[ev.status] || 'tag-upcoming'}">${STATUS_MAP[ev.status] || ev.status}</span>
                  <h3 style="margin-top:8px;">${h(ev.title)}</h3>
                  <div class="info-row"><i data-lucide="map-pin"></i> ${h(ev.location || '待定')}</div>
                  <div class="info-row"><i data-lucide="clock"></i> ${formatDateTime(ev.event_date)}</div>
                  ${ev.price ? `<div class="info-row"><i data-lucide="tag"></i> ${h(ev.price)}</div>` : ''}
                  ${ev.category ? `<div style="text-align:right;margin-top:6px;"><span class="cat-tag">${h(ev.category)}</span></div>` : ''}
                </div>
              </a>
            `).join('')}
          </div>
        </div>
      `;
    });

    // ===========================================
    // ROUTE: EVENT DETAIL
    // ===========================================
    route('/events/:id', async (params) => {
      const { data: event } = await sb.from('events').select('*').eq('id', params.id).single();
      if (!event) return '<div class="container section"><div class="empty-state"><i data-lucide="calendar"></i><p>活动未找到</p></div></div>';

      const descHtml = safeMarked(event.description || '暂无简介。');
      const guestsHtml = safeMarked(event.guests || '');

      return `
        <div class="container section">
          <a href="#/events" style="font-size:0.9rem;color:var(--color-text-2);margin-bottom:var(--space-3);display:inline-block;">← 返回活动列表</a>
          <div style="display:flex;gap:var(--space-4);flex-wrap:wrap;margin-top:var(--space-3);">
            <div style="width:100%;max-width:320px;flex-shrink:0;">
              <div style="aspect-ratio:2/3;border-radius:var(--radius-md);background:var(--color-bg-alt);overflow:hidden;display:flex;align-items:center;justify-content:center;">
                ${event.poster_url ? `<img src="${safeUrl(event.poster_url)}" alt="" style="width:100%;height:100%;object-fit:cover;">` : '<i data-lucide="image" style="width:48px;height:48px;color:var(--color-text-3);"></i>'}
              </div>
            </div>
            <div style="flex:1;min-width:280px;">
              ${statusTag(event.status)}
              <h1 style="margin-top:var(--space-1);">${h(event.title)}</h1>
              <div style="margin-top:var(--space-3);display:flex;flex-direction:column;gap:var(--space-2);">
                ${event.category ? `<div style="display:flex;align-items:center;gap:var(--space-2);"><i data-lucide="bookmark" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>分类：</strong>${h(event.category)}</div>` : ''}
                <div style="display:flex;align-items:center;gap:var(--space-2);"><i data-lucide="map-pin" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>地点：</strong>${h(event.location || '待定')}</div>
                <div style="display:flex;align-items:center;gap:var(--space-2);"><i data-lucide="clock" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>时间：</strong>${formatDateTime(event.event_date)}</div>
                ${event.guests ? `<div style="display:flex;align-items:flex-start;gap:var(--space-2);"><i data-lucide="user" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>嘉宾：</strong><span>${h(guestsHtml.replace(/<[^>]*>/g, ''))}</span></div>` : ''}
                ${event.price ? `<div style="display:flex;align-items:center;gap:var(--space-2);"><i data-lucide="tag" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>价格：</strong>${h(event.price)}</div>` : ''}
                ${event.link ? `<div style="display:flex;align-items:center;gap:var(--space-2);"><i data-lucide="external-link" style="color:var(--color-accent);width:20px;height:20px;"></i><strong>链接：</strong><a href="${safeUrl(event.link)}" target="_blank" class="btn btn-outline btn-sm">查看详情</a></div>` : ''}
              </div>
            </div>
          </div>
          <div class="card" style="margin-top:var(--space-4);">
            <div class="card-body md-content" style="max-width:none;"><h3>活动简介</h3>${descHtml}</div>
          </div>
        </div>
      `;
    });

    // ===========================================
    // ROUTE: NEW BOOKS EXPRESS — 新书速递
    // ===========================================
    route('/new-books', async () => {
      const user = store.get('user');
      const isAdmin = store.get('isAdmin');

      // Check staleness and trigger background refresh if > 24h
      const { data: lastScrape } = await sb.from('douban_new_books')
        .select('scraped_at').order('scraped_at', { ascending: false }).limit(1)
        .maybeSingle();

      const hoursSince = lastScrape?.scraped_at
        ? dayjs().diff(dayjs(lastScrape.scraped_at), 'hour')
        : 999;

      // Fire-and-forget refresh if stale
      if (hoursSince > 24 && isAdmin) {
        sb.auth.getSession().then(({ data: { session } }) => {
          if (!session) return;
          fetch(`${SUPABASE_URL}/functions/v1/scrape-douban`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${session.access_token}`
            },
            body: JSON.stringify({ force: false })
          }).catch(() => {});
        });
      }

      // Load books from cache (top 10 by review_count)
      const { data: books } = await sb.from('douban_new_books')
        .select('*').order('review_count', { ascending: false }).limit(10);

      // Load all wishlist votes for counting
      let wishCounts = {};
      let userWishes = new Set();

      if (books && books.length > 0) {
        const bookIds = books.map(b => b.id);
        const { data: allVotes } = await sb.from('reading_wishlist')
          .select('book_id').in('book_id', bookIds);
        (allVotes || []).forEach(v => {
          wishCounts[v.book_id] = (wishCounts[v.book_id] || 0) + 1;
        });

        if (user) {
          const { data: myVotes } = await sb.from('reading_wishlist')
            .select('book_id').eq('user_id', user.id).in('book_id', bookIds);
          (myVotes || []).forEach(v => userWishes.add(v.book_id));
        }
      }

      // Leaderboard: all books with >0 votes, sorted by count descending
      const { data: allBooks } = await sb.from('douban_new_books')
        .select('id, title, author, cover_url, douban_url');

      let lbWithVotes = [];
      if (allBooks && allBooks.length > 0) {
        const lbIds = allBooks.map(b => b.id);
        const { data: lbVotes } = await sb.from('reading_wishlist')
          .select('book_id').in('book_id', lbIds);
        const voteMap = {};
        (lbVotes || []).forEach(v => {
          voteMap[v.book_id] = (voteMap[v.book_id] || 0) + 1;
        });
        lbWithVotes = allBooks
          .map(b => ({ ...b, wish_count: voteMap[b.id] || 0 }))
          .filter(b => b.wish_count > 0)
          .sort((a, b) => b.wish_count - a.wish_count)
          .slice(0, 10);
      }

      // --- Render helpers ---
      const lastUpdateText = lastScrape?.scraped_at
        ? dayjs(lastScrape.scraped_at).format('YYYY年M月D日 HH:mm')
        : '暂无数据';
      const isStale = hoursSince > 24;

      // Book card HTML
      const booksHtml = books && books.length > 0
        ? books.map(b => {
            const count = wishCounts[b.id] || 0;
            const isWished = userWishes.has(b.id);
            return `
              <div class="new-book-card">
                <a href="${safeUrl(b.douban_url)}" target="_blank" rel="noopener" class="nb-cover">
                  ${b.cover_url
                    ? `<img src="${esc(proxyImg(b.cover_url))}" alt="" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='block';">`
                    : ''}
                  <i data-lucide="book" class="cover-fallback" style="${b.cover_url ? 'display:none;' : ''}"></i>
                </a>
                <div class="nb-body">
                  <h3><a href="${safeUrl(b.douban_url)}" target="_blank" rel="noopener">${h(b.title)}</a></h3>
                  <div class="nb-row"><span class="nb-label">作者</span>${h(b.author || '--')}</div>
                  ${b.translator ? `<div class="nb-row"><span class="nb-label">译者</span>${h(b.translator)}</div>` : ''}
                  <div class="nb-row"><span class="nb-label">出版方</span>${h(b.publisher || '--')}</div>
                  <div class="nb-row rating">${b.rating ? '⭐' + h(b.rating) + ' · ' + b.review_count + '人评价' : '暂无评分'}</div>
                  <div class="nb-actions">
                    <a href="${safeUrl(b.douban_url)}" target="_blank" rel="noopener" class="btn btn-outline btn-sm">豆瓣详情</a>
                    <button class="btn-wish${isWished ? ' active' : ''}"
                      data-book-id="${b.id}"
                      data-action="toggle-wish"
                      ${user ? '' : 'disabled title="请先登录后再标记想共读"'}>
                      <i data-lucide="heart" style="width:13px;height:13px;"></i>
                      想共读<span class="wish-count">${count > 0 ? ' ' + count : ''}</span>
                    </button>
                  </div>
                </div>
              </div>`;
          }).join('')
        : '<div class="empty-state"><i data-lucide="book"></i><p>暂无新书数据，请点击右上角「刷新」按钮获取最新数据</p></div>';

      // Leaderboard HTML
      const lbHtml = lbWithVotes.length > 0
        ? lbWithVotes.map((b, i) => {
            const rankCls = i === 0 ? 'top1' : i === 1 ? 'top2' : i === 2 ? 'top3' : 'rest';
            return `
              <div class="leaderboard-item">
                <div class="lb-rank ${rankCls}">${i + 1}</div>
                ${b.cover_url ? `<div class="lb-cover"><img src="${esc(proxyImg(b.cover_url))}" alt="" loading="lazy"></div>` : ''}
                <div class="lb-info">
                  <div class="lb-title">
                    <a href="${safeUrl(b.douban_url)}" target="_blank" rel="noopener">${h(b.title)}</a>
                  </div>
                  <div class="lb-meta">${h(b.author || '')}</div>
                </div>
                <div class="lb-votes"><i data-lucide="heart" style="width:13px;height:13px;"></i> ${b.wish_count}</div>
              </div>`;
          }).join('')
        : '<p style="color:var(--color-text-3);text-align:center;padding:var(--space-3) 0;">还没有人投票，快来为你感兴趣的新书点击「想共读」吧 ✨</p>';

      return `
        <div class="container section">
          <div class="page-header">
            <h1>新书速递</h1>
            <div class="subtitle">豆瓣新书速递 · 每日同步更新 · 发现值得共读的好书</div>
          </div>

          <div class="refresh-bar">
            <span class="last-update">
              <i data-lucide="clock" style="width:14px;height:14px;display:inline;vertical-align:-2px;"></i>
              最近同步：${lastUpdateText}
              ${isStale ? `<span class="refresh-hint">（数据已过期${isAdmin ? '，正在后台更新...' : '，等待管理员同步'}）</span>` : ''}
            </span>
            ${isAdmin ? `<button class="btn btn-outline btn-sm" id="btn-refresh-books">
              <i data-lucide="refresh-cw" style="width:14px;height:14px;"></i> 刷新数据
            </button>` : ''}
          </div>

          <div class="new-books-layout">
            <div class="new-books-main">
              <h2 style="margin-bottom:var(--space-3);display:flex;align-items:center;gap:8px;">
                <span>📚</span> 热门新书 Top 10
              </h2>
              <div class="new-book-grid">${booksHtml}</div>
            </div>
            <div class="new-books-side">
              <h2 style="margin-bottom:var(--space-3);display:flex;align-items:center;gap:8px;">
                <span>🏆</span> 想共读排行
              </h2>
              <div class="leaderboard">${lbHtml}</div>
            </div>
          </div>
        </div>`;
    });

    // ===========================================
    // LATIN AMERICA LITERARY MAP DATA
    // ===========================================
    const LATAM_COUNTRIES = [
      { id:'mx', isoNum:484, name:'墨西哥', flag:'🇲🇽',
        authors:[
          { name:'奥克塔维奥·帕斯', en:'Octavio Paz', bio:'1990年诺贝尔文学奖得主，墨西哥最伟大的诗人、散文家。作品融合超现实主义与拉美本土文化。', works:['《太阳石》','《孤独的迷宫》','《弓与琴》'] },
          { name:'卡洛斯·富恩特斯', en:'Carlos Fuentes', bio:'拉美文学爆炸核心人物，以实验性叙事探索墨西哥身份认同与历史。', works:['《最明净的地区》','《阿尔特米奥·克罗斯之死》','《奥拉》'] },
          { name:'胡安·鲁尔福', en:'Juan Rulfo', bio:'魔幻现实主义先驱，一生仅出版两部作品却影响深远，马尔克斯称其教会自己写作。', works:['《佩德罗·巴拉莫》','《燃烧的原野》'] }
        ]},
      { id:'gt', isoNum:320, name:'危地马拉', flag:'🇬🇹',
        authors:[
          { name:'米格尔·安赫尔·阿斯图里亚斯', en:'Miguel Ángel Asturias', bio:'1967年诺贝尔文学奖得主，魔幻现实主义先驱，作品根植于玛雅文化与反独裁斗争。', works:['《总统先生》','《玉米人》','《强风》'] }
        ]},
      { id:'cu', isoNum:192, name:'古巴', flag:'🇨🇺',
        authors:[
          { name:'阿莱霍·卡彭铁尔', en:'Alejo Carpentier', bio:'魔幻现实主义奠基人，"神奇现实"理论的提出者，将巴洛克美学融入拉美叙事。', works:['《人间王国》','《消失的脚步》','《光明世纪》'] },
          { name:'何塞·马蒂', en:'José Martí', bio:'古巴民族英雄、现代主义诗歌先驱，以热血文字呼唤拉美独立与团结。', works:['《伊斯马埃利约》','《纯朴的诗》','《我们的美洲》'] }
        ]},
      { id:'ni', isoNum:558, name:'尼加拉瓜', flag:'🇳🇮',
        authors:[
          { name:'鲁文·达里奥', en:'Rubén Darío', bio:'拉美现代主义诗歌之父，革新西班牙语诗歌韵律与意象，影响遍及整个西语世界。', works:['《蓝》','《亵渎的散文》','《生命与希望之歌》'] }
        ]},
      { id:'co', isoNum:170, name:'哥伦比亚', flag:'🇨🇴',
        authors:[
          { name:'加西亚·马尔克斯', en:'Gabriel García Márquez', bio:'1982年诺贝尔文学奖得主，魔幻现实主义巅峰代表，二十世纪最伟大的小说家之一。', works:['《百年孤独》','《霍乱时期的爱情》','《族长的秋天》'] },
          { name:'阿尔瓦罗·穆蒂斯', en:'Álvaro Mutis', bio:'诗人、小说家，马尔克斯挚友，以航海史诗《马科洛尔的冒险》系列闻名。', works:['《阿米尔巴尔》','《伊洛娜随雨而至》'] }
        ]},
      { id:'ve', isoNum:862, name:'委内瑞拉', flag:'🇻🇪',
        authors:[
          { name:'罗慕洛·加列戈斯', en:'Rómulo Gallegos', bio:'委内瑞拉最伟大的小说家，以描绘大草原与民族精神闻名，曾短暂担任总统。', works:['《堂娜芭芭拉》','《坎塔克拉罗》'] }
        ]},
      { id:'ec', isoNum:218, name:'厄瓜多尔', flag:'🇪🇨',
        authors:[
          { name:'豪尔赫·伊卡萨', en:'Jorge Icaza', bio:'土著主义文学代表，以《瓦西蓬戈》揭露印第安人的悲惨命运，震撼拉美文坛。', works:['《瓦西蓬戈》','《混血儿》'] }
        ]},
      { id:'pe', isoNum:604, name:'秘鲁', flag:'🇵🇪',
        authors:[
          { name:'巴尔加斯·略萨', en:'Mario Vargas Llosa', bio:'2010年诺贝尔文学奖得主，结构现实主义大师，以复调叙事探索权力与自由。', works:['《城市与狗》','《绿房子》','《酒吧长谈》'] },
          { name:'塞萨尔·巴列霍', en:'César Vallejo', bio:'二十世纪最伟大的西班牙语诗人之一，以先锋语言表达人类苦难与救赎。', works:['《特里尔塞》','《人类的诗篇》','《黑色先驱》'] }
        ]},
      { id:'bo', isoNum:68, name:'玻利维亚', flag:'🇧🇴',
        authors:[
          { name:'海梅·萨恩斯', en:'Jaime Sáenz', bio:'玻利维亚最重要的现代诗人，作品融合安第斯神秘主义与存在主义哲思。', works:['《死亡之触》','《访客》'] }
        ]},
      { id:'cl', isoNum:152, name:'智利', flag:'🇨🇱',
        authors:[
          { name:'巴勃罗·聂鲁达', en:'Pablo Neruda', bio:'1971年诺贝尔文学奖得主，二十世纪最伟大的诗人之一，爱情与政治的诗篇传遍世界。', works:['《二十首情诗和一首绝望的歌》','《漫歌》','《元素的颂歌》'] },
          { name:'加夫列拉·米斯特拉尔', en:'Gabriela Mistral', bio:'1945年诺贝尔文学奖得主，拉美第一位诺奖作家，以深沉母性与悲悯情怀动人。', works:['《绝望》','《柔情》','《塔拉》'] },
          { name:'罗贝托·波拉尼奥', en:'Roberto Bolaño', bio:'后爆炸时代最具影响力的拉美作家，以《2666》重塑当代西语文学版图。', works:['《2666》','《荒野侦探》','《遥远的星辰》'] }
        ]},
      { id:'py', isoNum:600, name:'巴拉圭', flag:'🇵🇾',
        authors:[
          { name:'奥古斯托·罗亚·巴斯托斯', en:'Augusto Roa Bastos', bio:'巴拉圭最伟大的作家，塞万提斯奖得主，以《人子》三部曲书写巴拉圭民族史诗。', works:['《人子》','《我，至高无上者》'] }
        ]},
      { id:'ar', isoNum:32, name:'阿根廷', flag:'🇦🇷',
        authors:[
          { name:'豪尔赫·路易斯·博尔赫斯', en:'Jorge Luis Borges', bio:'二十世纪最具原创性的作家之一，以迷宫、镜子、图书馆构建形而上学叙事宇宙。', works:['《小径分岔的花园》','《阿莱夫》','《虚构集》'] },
          { name:'胡利奥·科塔萨尔', en:'Julio Cortázar', bio:'拉美文学爆炸核心人物，以碎片化叙事打破现实主义传统，重新定义短篇小说。', works:['《跳房子》','《动物寓言集》','《万火归一》'] },
          { name:'埃内斯托·萨瓦托', en:'Ernesto Sabato', bio:'物理学家出身的小说家，以存在主义视角探索理性与疯狂的边界。', works:['《隧道》','《英雄与坟墓》'] }
        ]},
      { id:'uy', isoNum:858, name:'乌拉圭', flag:'🇺🇾',
        authors:[
          { name:'胡安·卡洛斯·奥内蒂', en:'Juan Carlos Onetti', bio:'拉美心理小说先驱，以虚构城市圣玛利亚构建孤独绝望的叙事迷宫。', works:['《造船厂》','《短暂的生命》','《收尸人》'] },
          { name:'马里奥·贝内德蒂', en:'Mario Benedetti', bio:'乌拉圭最受爱戴的作家，以平实语言书写普通人生活、爱情与流亡。', works:['《休战》','《感谢火焰》'] }
        ]},
      { id:'br', isoNum:76, name:'巴西', flag:'🇧🇷',
        authors:[
          { name:'马查多·德·阿西斯', en:'Machado de Assis', bio:'巴西文学之父，以冷峻讽刺与心理洞察开创拉美现实主义小说先河。', works:['《布拉兹·库巴斯的死后回忆》','《堂卡斯穆罗》'] },
          { name:'克拉丽丝·李斯佩克特', en:'Clarice Lispector', bio:'二十世纪最重要的巴西作家之一，以独特内省风格探索存在与语言的边界。', works:['《星辰时刻》','《靠近狂野之心》'] },
          { name:'若热·亚马多', en:'Jorge Amado', bio:'巴西最广为人知的作家，以热情奔放的笔触描绘巴伊亚的人情风土。', works:['《加布里埃拉、丁香与肉桂》','《弗洛尔姑娘和她的两个丈夫》'] }
        ]},
    ];

    // ===========================================
    // ROUTE: LATIN AMERICA LITERARY MAP (Leaflet + GeoJSON)
    // ===========================================
    route('/latin-america', async () => {
      const countries = LATAM_COUNTRIES;

      // Default intro panel
      const introPanel = `
        <h2>🌎 拉丁美洲文学地图</h2>
        <div class="panel-intro">
          拉丁美洲是二十世纪世界文学的爆炸原点。从魔幻现实主义到结构现实主义，
          从博尔赫斯的迷宫到聂鲁达的情诗，这片大陆孕育了最富想象力的文学图景。<br><br>
          <strong>点击地图上的国家</strong>，发现那些改变了世界文学版图的作家与作品。
        </div>
        <div style="margin-top:var(--space-3);padding-top:var(--space-3);border-top:1px solid var(--color-border);">
          <div style="font-size:0.78rem;color:var(--color-text-3);margin-bottom:6px;">🏆 诺贝尔文学奖得主（拉美）</div>
          <div style="font-size:0.78rem;color:var(--color-text-2);line-height:1.8;">
            1945 · 🇨🇱 加夫列拉·米斯特拉尔<br>
            1967 · 🇬🇹 米格尔·阿斯图里亚斯<br>
            1971 · 🇨🇱 巴勃罗·聂鲁达<br>
            1982 · 🇨🇴 加西亚·马尔克斯<br>
            1990 · 🇲🇽 奥克塔维奥·帕斯<br>
            2010 · 🇵🇪 巴尔加斯·略萨
          </div>
        </div>
      `;

      // Country tags
      const tagsHtml = countries.map(c =>
        `<span class="latam-tag" data-country="${c.id}">${c.flag} ${c.name}</span>`
      ).join('');

      return `
        <div class="container section">
          <div class="page-header">
            <h1>西语文学专区</h1>
            <div class="subtitle">拉丁美洲文学地图 · 探索西语世界的文学瑰宝</div>
          </div>

          <div class="latam-layout">
            <div class="latam-map-wrap" id="latam-map-wrap">
              <div id="latam-leaflet-map" style="width:100%;height:550px;border-radius:var(--radius-md);border:1px solid var(--color-border);box-shadow:var(--shadow-sm);"></div>
            </div>
            <div class="latam-panel" id="latam-panel">
              ${introPanel}
            </div>
          </div>

          <div class="latam-tags" id="latam-tags">
            ${tagsHtml}
          </div>
        </div>`;
    });

    // ===========================================
    // ROUTE: PROFILE
    // ===========================================
    route('/profile', async () => {
      const profile = store.get('profile');
      if (!profile) return '<div class="container section"><div class="empty-state"><i data-lucide="loader"></i><p>加载中...</p></div></div>';

      // Reset calendar to current month on fresh navigation
      const now = dayjs();
      calYear = now.year();
      calMonth = now.month() + 1;
      calCheckinsData = await getMonthCheckinsFull(calYear, calMonth);
      const todayStr = now.format('YYYY-MM-DD');
      const todayCheckin = calCheckinsData.find(c => c.checkin_date === todayStr);

      // Build calendar grid HTML
      function calGridHTML() {
        const map = new Map(calCheckinsData.map(c => [c.checkin_date, c]));
        const firstDay = dayjs(`${calYear}-${String(calMonth).padStart(2,'0')}-01`);
        const daysInMonth = firstDay.daysInMonth();
        const startDayOfWeek = firstDay.day();
        const prevMonthDays = firstDay.subtract(1, 'day').daysInMonth();

        let cells = '';
        ['日','一','二','三','四','五','六'].forEach(d => { cells += `<div class="day-name">${d}</div>`; });
        for (let i = startDayOfWeek - 1; i >= 0; i--) {
          cells += `<div class="day other-month">${prevMonthDays - i}</div>`;
        }
        for (let d = 1; d <= daysInMonth; d++) {
          const dateStr = firstDay.date(d).format('YYYY-MM-DD');
          const checkin = map.get(dateStr);
          let cls = 'day';
          if (checkin) {
            cls += ' checked';
          } else if (dateStr === todayStr) cls += ' today';
          else if (dayjs(dateStr).isAfter(now, 'day')) cls += ' future';
          const style = (checkin && checkin.mood_color)
            ? `style="--mood-dot:${safeColor(checkin.mood_color, '#c17d4b')}"` : '';
          const dataDate = checkin ? `data-date="${esc(dateStr)}"` : '';
          cells += `<div class="${cls}" ${style} ${dataDate}><span>${d}</span></div>`;
        }
        const totalCells = startDayOfWeek + daysInMonth;
        const remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
        for (let d = 1; d <= remaining; d++) {
          cells += `<div class="day other-month">${d}</div>`;
        }
        return cells;
      }

      return `
        <div class="container section">
          <div style="display:flex;gap:var(--space-4);flex-wrap:wrap;align-items:flex-start;">
            <div style="width:100%;max-width:320px;">
              <div class="card">
                <div class="card-body" style="text-align:center;">
                  <div style="width:80px;height:80px;border-radius:50%;background:var(--color-accent-bg);margin:0 auto var(--space-2);display:flex;align-items:center;justify-content:center;font-size:1.8rem;font-weight:700;color:var(--color-accent);overflow:hidden;">
                    ${profile.avatar_url ? `<img src="${safeUrl(profile.avatar_url)}" alt="" style="width:100%;height:100%;object-fit:cover;">` : h((profile.display_name || '?')[0].toUpperCase())}
                  </div>
                  <h3>${h(profile.display_name)}</h3>
                  ${profile.bio ? `<p style="color:var(--color-text-2);font-size:0.9rem;margin:8px 0;">${h(profile.bio)}</p>` : ''}
                  ${profile.city ? `<div style="font-size:0.85rem;color:var(--color-text-3);"><i data-lucide="map-pin" style="width:14px;height:14px;display:inline;vertical-align:-2px;"></i> ${h(profile.city)}</div>` : ''}
                  <a href="#/profile/edit" class="btn btn-outline btn-sm" style="margin-top:var(--space-2);">编辑资料</a>
                </div>
              </div>
            </div>
            <div style="flex:1;min-width:300px;">
              <div class="card" style="margin-bottom:var(--space-3);">
                <div class="card-body" style="text-align:center;">
                  <h4 style="margin-bottom:var(--space-2);">每日阅读签到</h4>
                  <button class="btn btn-primary ${todayCheckin ? 'btn-ghost' : ''}" id="checkin-btn">
                    ${todayCheckin ? '编辑今日签到' : '📖 今日签到'}
                  </button>
                </div>
              </div>
              <div class="card">
                <div class="card-body">
                  <div class="calendar">
                    <div class="calendar-header">
                      <button class="btn btn-ghost btn-sm" id="cal-prev"><i data-lucide="chevron-left" style="width:18px;height:18px;"></i></button>
                      <h4 id="cal-month-label">${calYear}年${calMonth}月</h4>
                      <button class="btn btn-ghost btn-sm" id="cal-next"><i data-lucide="chevron-right" style="width:18px;height:18px;"></i></button>
                    </div>
                    <div class="calendar-grid" id="cal-grid">${calGridHTML()}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      `;
    });

    // ===========================================
    // ROUTE: PROFILE EDIT
    // ===========================================
    route('/profile/edit', () => {
      const profile = store.get('profile');
      if (!profile) return '';
      return `
        <div class="container section" style="max-width:560px;">
          <h2 style="margin-bottom:var(--space-3);">编辑资料</h2>
          <div class="card"><div class="card-body">
            <form id="profile-form">
              <div class="form-group"><label>显示名称</label><input type="text" name="display_name" value="${esc(profile.display_name || '')}" required></div>
              <div class="form-group"><label>个人简介</label><textarea name="bio">${h(profile.bio || '')}</textarea></div>
              <div class="form-group"><label>微信号</label><input type="text" name="wechat_id" value="${esc(profile.wechat_id || '')}"></div>
              <div class="form-group"><label>所在城市</label><input type="text" name="city" value="${esc(profile.city || '')}"></div>
              <div class="form-group"><label>头像链接</label><input type="url" name="avatar_url" value="${esc(profile.avatar_url || '')}" placeholder="https://..."></div>
              <button type="submit" class="btn btn-primary">保存</button>
              <a href="#/profile" class="btn btn-ghost">取消</a>
            </form>
          </div></div>
        </div>
      `;
    });

    document.addEventListener('submit', async (e) => {
      if (e.target.id === 'profile-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        const updates = {
          display_name: fd.get('display_name'),
          bio: fd.get('bio'),
          wechat_id: fd.get('wechat_id'),
          city: fd.get('city'),
          avatar_url: fd.get('avatar_url'),
          updated_at: new Date().toISOString()
        };
        const { error } = await sb.from('profiles').update(updates).eq('id', store.get('user').id);
        if (error) { toast('保存失败：' + error.message, 'error'); return; }
        store.set('profile', { ...store.get('profile'), ...updates });
        toast('资料已更新');
        router.navigate('/profile');
      }
      if (e.target.id === 'checkin-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        const isEdit = fd.get('is_edit') === '1';
        const dateStr = fd.get('checkin_date');
        const payload = {
          book_title: fd.get('book_title') || null,
          excerpt: fd.get('excerpt') || null,
          reflection: fd.get('reflection') || null,
          mood_color: fd.get('mood_color') || null
        };
        const success = isEdit
          ? await updateCheckin(dateStr, payload)
          : await doCheckin(payload);
        if (success) {
          const modal = e.target.closest('.modal-overlay');
          if (modal) modal.remove();
          await refreshCalendar();
        }
      }
    });

    // ===========================================
    // Calendar & Checkin click delegation
    // ===========================================
    document.addEventListener('click', async (e) => {
      // Calendar: previous month
      const calPrev = e.target.closest('#cal-prev');
      if (calPrev) {
        calMonth--;
        if (calMonth < 1) { calMonth = 12; calYear--; }
        await refreshCalendar();
        return;
      }
      // Calendar: next month
      const calNext = e.target.closest('#cal-next');
      if (calNext) {
        calMonth++;
        if (calMonth > 12) { calMonth = 1; calYear++; }
        await refreshCalendar();
        return;
      }
      // Checkin button
      const checkinBtn = e.target.closest('#checkin-btn');
      if (checkinBtn) {
        const today = dayjs().format('YYYY-MM-DD');
        const todayCheckin = calCheckinsData.find(c => c.checkin_date === today);
        showCheckinForm(todayCheckin || null);
        return;
      }
      // Calendar day click
      const calDay = e.target.closest('#cal-grid .day.checked');
      if (calDay && calDay.dataset.date) {
        const checkin = await getCheckinDetail(calDay.dataset.date);
        if (checkin) showCheckinDetail(checkin);
        return;
      }
      // Edit checkin from detail modal
      const editBtn = e.target.closest('#edit-checkin-btn');
      if (editBtn) {
        const checkin = await getCheckinDetail(editBtn.dataset.date);
        if (checkin) {
          const overlay = editBtn.closest('.modal-overlay');
          if (overlay) overlay.remove();
          showCheckinForm(checkin);
        }
        return;
      }
    });

    // ===========================================
    // ROUTE: ADMIN
    // ===========================================
    route('/admin', async () => {
      const config = await loadConfig();
      const books = await loadBooks();
      const events = await loadEvents();

      return `
        <div class="container section">
          <div class="page-header"><h1>管理后台</h1></div>
          <div class="tabs" id="admin-tabs">
            <button class="tab active" data-tab="rules">群规编辑</button>
            <button class="tab" data-tab="books">书籍管理</button>
            <button class="tab" data-tab="events">活动管理</button>
          </div>
          <div id="admin-tab-rules">
            <h3 style="margin-bottom:var(--space-2);">群规</h3>
            <form id="rules-form">
              <div class="form-group"><label>共读群公约（Markdown）</label><textarea name="group_rules" style="min-height:200px;">${h(config.group_rules || '')}</textarea></div>
              <div class="form-group"><label>共读计划介绍（Markdown）</label><textarea name="reading_plan_intro" style="min-height:120px;">${h(config.reading_plan_intro || '')}</textarea></div>
              <button type="submit" class="btn btn-primary">保存设置</button>
            </form>
            <hr style="margin:var(--space-4) 0;border-color:var(--color-border);">
            <h3 style="margin-bottom:var(--space-2);">添加新书</h3>
            <button class="btn btn-outline" id="btn-add-book">+ 添加书籍</button>
            <div style="margin-top:var(--space-3);">
              <h4 style="margin-bottom:var(--space-1);">现有书籍</h4>
              ${books.map(b => `
                <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
                  <span>${h(b.title)}${b.start_date && b.end_date ? '（' + dayjs(b.start_date).format('YYYY.MM.DD') + '-' + dayjs(b.end_date).format('YYYY.MM.DD') + '）' : ''} ${statusTag(b.status)}</span>
                  <div>
                    <button class="btn btn-ghost btn-sm btn-edit-book" data-id="${b.id}">编辑</button>
                    <button class="btn btn-danger btn-sm btn-del-book" data-id="${b.id}">删除</button>
                  </div>
                </div>
              `).join('')}
            </div>
          </div>
          <div id="admin-tab-events" style="display:none;">
            <h3 style="margin-bottom:var(--space-2);">添加线下活动</h3>
            <button class="btn btn-outline" id="btn-add-event">+ 添加活动</button>
            <div style="margin-top:var(--space-3);">
              <h4 style="margin-bottom:var(--space-1);">现有活动</h4>
              ${events.map(ev => `
                <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
                  <span>${h(ev.title)}（${formatDateTime(ev.event_date)}${ev.location ? ' · ' + h(ev.location) : ''}） ${statusTag(ev.status)}</span>
                  <div>
                    <button class="btn btn-ghost btn-sm btn-edit-event" data-id="${ev.id}">编辑</button>
                    <button class="btn btn-danger btn-sm btn-del-event" data-id="${ev.id}">删除</button>
                  </div>
                </div>
              `).join('')}
            </div>
          </div>
          <div id="admin-tab-books" style="display:none;">
            <h3 style="margin-bottom:var(--space-2);">添加新书</h3>
            <button class="btn btn-outline" id="btn-add-book2">+ 添加书籍</button>
            <div style="margin-top:var(--space-3);">
              ${books.map(b => `
                <div style="display:flex;align-items:center;justify-content:space-between;padding:var(--space-1) 0;border-bottom:1px solid var(--color-border);">
                  <span>${h(b.title)}${b.start_date && b.end_date ? '（' + dayjs(b.start_date).format('YYYY.MM.DD') + '-' + dayjs(b.end_date).format('YYYY.MM.DD') + '）' : ''} ${statusTag(b.status)}</span>
                  <div>
                    <button class="btn btn-ghost btn-sm btn-edit-book" data-id="${b.id}">编辑</button>
                    <button class="btn btn-danger btn-sm btn-del-book" data-id="${b.id}">删除</button>
                  </div>
                </div>
              `).join('')}
            </div>
          </div>
        </div>
      `;
    });

    // Admin tab switching
    document.addEventListener('click', (e) => {
      const tab = e.target.closest('#admin-tabs .tab');
      if (!tab) return;
      document.querySelectorAll('#admin-tabs .tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      ['rules','books','events'].forEach(t => {
        const el = document.getElementById('admin-tab-' + t);
        if (el) el.style.display = tab.dataset.tab === t ? '' : 'none';
      });
    });

    // Admin: save rules
    document.addEventListener('submit', async (e) => {
      if (e.target.id === 'rules-form') {
        e.preventDefault();
        const fd = new FormData(e.target);
        for (const [key, value] of fd.entries()) {
          await sb.from('site_config').upsert({ key, value }, { onConflict: 'key' });
        }
        await loadConfig(); // refresh cached config
        toast('设置已保存');
      }
    });

    // ===========================================
    // VISUAL FORM BUILDERS — v2 unified
    // ===========================================
    function actItem(a) { a=a||{}; return `
      <div class="builder-item">
        <div class="b-row">
          <select name="act_type" style="max-width:110px">${ACT_TYPES.map(t=>`<option value="${t}" ${a.type===t?'selected':''}>${t}</option>`).join('')}</select>
          <select name="act_status" style="max-width:100px">${ACT_STATUSES.map(s=>`<option value="${s}" ${a.status===s?'selected':''}>${s}</option>`).join('')}</select>
          <input name="act_title" value="${esc(a.title)}" placeholder="活动标题 *" style="flex:2" required>
          <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
        </div>
        <div class="b-row">
          <input name="act_time" value="${esc(a.time)}" placeholder="时间 如 19:30 或 2月1日" style="flex:1">
          <input name="act_meeting_link" value="${esc(a.meeting_link)}" placeholder="会议链接" style="flex:1">
          <input name="act_replay_link" value="${esc(a.replay_link)}" placeholder="回放链接" style="flex:1">
        </div>
        <div class="b-row">
          <input name="act_guests" value="${esc(a.guests)}" placeholder="嘉宾（可选）">
        </div>
        <div class="b-row">
          <input name="act_desc" value="${esc(a.description)}" placeholder="描述（可选）">
        </div>
      </div>`;
    }
    function ednItem(e) { e=e||{}; return `
      <div class="builder-item">
        <div class="b-row">
          <input name="edn_name" value="${esc(e.name)}" placeholder="版本名称 *" style="flex:2" required>
          <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
        </div>
        <div class="b-row">
          <input name="edn_translator" value="${esc(e.translator)}" placeholder="译者">
          <input name="edn_publisher" value="${esc(e.publisher)}" placeholder="出版方">
        </div>
        <div class="b-row">
          <input name="edn_pros" value="${esc(e.pros)}" placeholder="优点">
          <input name="edn_cons" value="${esc(e.cons)}" placeholder="缺点">
        </div>
        <div class="b-row">
          <input name="edn_buy_link" value="${esc(e.buy_link)}" placeholder="购买链接">
          <input name="edn_douban_link" value="${esc(e.douban_link)}" placeholder="豆瓣链接">
        </div>
      </div>`;
    }
    function chatItem(c) { c=c||{}; return `
      <div class="builder-item">
        <div class="b-row">
          <input name="chat_topic" value="${esc(c.topic)}" placeholder="干货主题 *" style="flex:2" required>
          <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
        </div>
        <div class="b-row">
          <input name="chat_speaker" value="${esc(c.speaker)}" placeholder="主发言人">
        </div>
        <div class="b-row">
          <textarea name="chat_content" placeholder="详细内容（Markdown）" style="min-height:60px;width:100%;">${esc(c.content)}</textarea>
        </div>
      </div>`;
    }
    function resItem(r) { r=r||{}; return `
      <div class="builder-item">
        <div class="b-row">
          <input name="res_title" value="${esc(r.title)}" placeholder="标题" style="flex:2">
          <button type="button" class="btn-remove-row" onclick="this.closest('.builder-item').remove()">✕</button>
        </div>
        <div class="b-row">
          <input name="res_url" value="${esc(r.url)}" placeholder="链接（可选）">
          <input name="res_desc" value="${esc(r.description)}" placeholder="描述（可选）">
        </div>
      </div>`;
    }

    // Admin: add/edit book form
    function showBookForm(bookData = null) {
      const isEdit = !!bookData;
      const book = bookData || { title:'', author:'', author_country:'', author_gender:'', translator:'', translator_gender:'', publisher:'', word_count:'', cover_url:'', genre:'文学', description:'', author_bio:'', historical_context:'', status:'upcoming', edition_guide:'[]', edition_notes:'', reading_schedule:'{"summary":"","pdf_url":""}', host:'', host_intro:'', host_notes:'', activities:'[]', chatsubstance:'[]', resources:'{"extended_reading":[],"text_materials":[],"film_resources":[],"other":[]}', start_date:'', end_date:'' };
      const genres = ['文学','历史','哲学','科幻','社科','心理','传记','商业','科普','其他'];
      // Parse JSONB data for visual builders
      let acts=[], edns=[], chats=[], extR=[], txtM=[], filmR=[], otherR=[];
      try { acts = typeof book.activities==='string' ? JSON.parse(book.activities||'[]') : (book.activities||[]); } catch(e){}
      try { edns = typeof book.edition_guide==='string' ? JSON.parse(book.edition_guide||'[]') : (book.edition_guide||[]); } catch(e){}
      try { chats = typeof book.chatsubstance==='string' ? JSON.parse(book.chatsubstance||'[]') : (book.chatsubstance||[]); } catch(e){}
      try {
        const res = typeof book.resources==='string' ? JSON.parse(book.resources||'{}') : (book.resources||{});
        extR = res.extended_reading||[]; txtM = res.text_materials||[]; filmR = res.film_resources||[]; otherR = res.other||[];
      } catch(e){}
      let scheduleForForm = { summary: '', pdf_url: '' };
      try {
        scheduleForForm = typeof book.reading_schedule === 'string'
          ? JSON.parse(book.reading_schedule || '{}')
          : (book.reading_schedule || {});
      } catch(e) {
        scheduleForForm = { summary: String(book.reading_schedule || ''), pdf_url: '' };
      }

      const formHtml = `
        <form id="book-edit-form" style="max-height:70vh;overflow-y:auto;">
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--space-2);">
            <div class="form-group"><label>书名 *</label><input type="text" name="title" value="${esc(book.title)}" required></div>
            <div class="form-group"><label>作者 *</label><input type="text" name="author" value="${esc(book.author)}" required></div>
            <div class="form-group"><label>作者国别</label><input type="text" name="author_country" value="${esc(book.author_country || '')}"></div>
            <div class="form-group"><label>作者性别</label><input type="text" name="author_gender" value="${esc(book.author_gender || '')}"></div>
            <div class="form-group"><label>译者</label><input type="text" name="translator" value="${esc(book.translator || '')}"></div>
            <div class="form-group"><label>译者性别</label><input type="text" name="translator_gender" value="${esc(book.translator_gender || '')}"></div>
            <div class="form-group"><label>出版方</label><input type="text" name="publisher" value="${esc(book.publisher || '')}"></div>
            <div class="form-group"><label>字数</label><input type="number" name="word_count" value="${esc(book.word_count || '')}"></div>
            <div class="form-group"><label>类型 *</label><select name="genre" required>${genres.map(g => `<option value="${g}" ${book.genre === g ? 'selected' : ''}>${g}</option>`).join('')}</select></div>
            <div class="form-group"><label>共读状态 *</label><select name="status">
              <option value="upcoming" ${book.status === 'upcoming' ? 'selected' : ''}>即将开读</option>
              <option value="active" ${book.status === 'active' ? 'selected' : ''}>正在共读</option>
              <option value="completed" ${book.status === 'completed' ? 'selected' : ''}>已读完</option>
            </select></div>
            <div class="form-group"><label>开始日期 *</label><input type="date" name="start_date" value="${esc(book.start_date || '')}" required></div>
            <div class="form-group"><label>结束日期 *</label><input type="date" name="end_date" value="${esc(book.end_date || '')}" required></div>
          </div>

          <!-- Cover image: URL + upload -->
          <div class="form-group">
            <label>封面图 *</label>
            <div class="cover-upload">
              <div class="cover-preview" id="cover-preview">
                ${book.cover_url ? `<img src="${safeUrl(book.cover_url)}" alt="">` : '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>'}
              </div>
              <div class="cover-inputs">
                <input type="url" name="cover_url" value="${esc(book.cover_url || '')}" placeholder="粘贴图片 URL" id="cover-url-input" required>
                <div class="divider-text">或</div>
                <input type="file" accept="image/*" id="cover-file-input" style="font-size:0.85rem;">
              </div>
            </div>
          </div>

          <div style="display:flex;align-items:center;gap:8px;margin-bottom:var(--space-1);">
            <button type="button" class="btn btn-outline btn-sm" id="btn-ai-fill">🤖 AI 自动填充简介</button>
            <span style="font-size:0.78rem;color:var(--color-text-3);">AI 自动编写书籍简介、作者简介、时代背景（不剧透）</span>
          </div>
          <div class="form-group"><label>书籍简介（Markdown）</label><textarea name="description" style="min-height:60px;">${h(book.description || '')}</textarea></div>
          <div class="form-group"><label>作者简介（Markdown）</label><textarea name="author_bio" style="min-height:60px;">${h(book.author_bio || '')}</textarea></div>
          <div class="form-group"><label>创作时代背景（Markdown）</label><textarea name="historical_context" style="min-height:60px;">${h(book.historical_context || '')}</textarea></div>
          <div class="form-group"><label>版本建议简述（Markdown）</label><textarea name="edition_notes" style="min-height:60px;" placeholder="版本选择的总体建议...">${h(book.edition_notes || '')}</textarea></div>

          <!-- Visual Builder: Edition Guide -->
          <div class="builder-section">
            <label>📖 版本建议</label>
            <div class="builder-items" id="builder-editions">${edns.length ? edns.map(ednItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无版本</div>'}</div>
            <button type="button" class="btn-add-row" data-action="add-edition">+ 添加版本</button>
          </div>

          <div class="form-group"><label>共读时间计划简述（Markdown）</label><textarea name="schedule_summary" style="min-height:80px;">${h(scheduleForForm.summary || '')}</textarea></div>
          <div class="form-group">
            <label>时间计划 PDF</label>
            <div style="display:flex;gap:var(--space-2);align-items:center;">
              <input type="file" id="schedule-pdf-input" accept=".pdf" style="flex:1;">
              <input type="hidden" name="schedule_pdf_url" id="schedule-pdf-url" value="${esc(scheduleForForm.pdf_url || '')}">
            </div>
            <div id="schedule-pdf-name" style="font-size:0.82rem;color:var(--color-text-2);margin-top:4px;">${scheduleForForm.pdf_url ? '已上传：' + h(String(scheduleForForm.pdf_url).split('/').pop()) : ''}</div>
          </div>
          <div class="form-group"><label>领读人</label><input type="text" name="host" value="${esc(book.host || '')}" placeholder="领读人姓名"></div>
          <div class="form-group"><label>领读人简介（Markdown）</label><textarea name="host_intro" style="min-height:80px;">${h(book.host_intro || '')}</textarea></div>
          <div class="form-group"><label>灵沁碎碎念（Markdown）</label><textarea name="host_notes" style="min-height:80px;">${h(book.host_notes || '')}</textarea></div>

          <!-- Visual Builder: Activities (unified) -->
          <div class="builder-section">
            <label>📅 活动安排</label>
            <div class="builder-items" id="builder-acts">${acts.length ? acts.map(actItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无活动</div>'}</div>
            <button type="button" class="btn-add-row" data-action="add-activity">+ 添加活动</button>
          </div>

          <!-- Visual Builder: Chat Substance -->
          <div class="builder-section">
            <label>💬 聊天干货</label>
            <div class="builder-items" id="builder-chats">${chats.length ? chats.map(chatItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无干货</div>'}</div>
            <button type="button" class="btn-add-row" data-action="add-chat">+ 添加聊天干货</button>
          </div>

          <!-- Visual Builder: Resources -->
          <div class="builder-section">
            <label>📚 资源材料</label>
            <div class="res-section">
              <h5>延伸读物</h5>
              <div class="builder-items" id="builder-ext">${extR.length ? extR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
              <button type="button" class="btn-add-row" data-action="add-ext">+ 添加延伸读物</button>
            </div>
            <div class="res-section">
              <h5>文字材料</h5>
              <div class="builder-items" id="builder-txt">${txtM.length ? txtM.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
              <button type="button" class="btn-add-row" data-action="add-txt">+ 添加文字材料</button>
            </div>
            <div class="res-section">
              <h5>影视资源</h5>
              <div class="builder-items" id="builder-film">${filmR.length ? filmR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
              <button type="button" class="btn-add-row" data-action="add-film">+ 添加影视资源</button>
            </div>
            <div class="res-section">
              <h5>其他</h5>
              <div class="builder-items" id="builder-other">${otherR.length ? otherR.map(resItem).join('') : '<div class="builder-item" style="text-align:center;color:var(--color-text-3);padding:12px;font-size:0.85rem;">暂无</div>'}</div>
              <button type="button" class="btn-add-row" data-action="add-other">+ 添加其他</button>
            </div>
          </div>

          <button type="submit" class="btn btn-primary">${isEdit ? '保存修改' : '添加书籍'}</button>
          <input type="hidden" name="book_id" value="${esc(book.id || '')}">
        </form>`;
      const modal = showModal(isEdit ? '编辑书籍' : '添加书籍', formHtml, () => {
        document.removeEventListener('submit', bookFormHandler);
      });
      document.addEventListener('submit', bookFormHandler);
      function bookFormHandler(e) {
        if (e.target.id !== 'book-edit-form') return;
        e.preventDefault();
        const fd = new FormData(e.target);
        const data = Object.fromEntries(fd.entries());

        // Collect from visual builders
        function collectItems(containerId, fields) {
          const items = document.querySelectorAll(`#${containerId} .builder-item`);
          return Array.from(items).map(item => {
            const obj = {};
            fields.forEach(f => { const el = item.querySelector(`[name="${f}"]`); if (el) obj[f] = el.value; });
            return obj;
          }).filter(obj => Object.values(obj).some(v => v.trim()));
        }

        // Edition guide
        const edns = collectItems('builder-editions', ['edn_name','edn_translator','edn_publisher','edn_pros','edn_cons','edn_buy_link','edn_douban_link']).map(o => ({
          name: o.edn_name||'', translator: o.edn_translator||'', publisher: o.edn_publisher||'',
          pros: o.edn_pros||'', cons: o.edn_cons||'', buy_link: o.edn_buy_link||'', douban_link: o.edn_douban_link||''
        }));
        data.edition_guide = JSON.stringify(edns);

        // Activities (unified)
        data.activities = collectItems('builder-acts', ['act_type','act_title','act_time','act_status','act_meeting_link','act_replay_link','act_guests','act_desc']).map(o => ({
          type: o.act_type||'导读预热', title: o.act_title||'', time: o.act_time||'',
          status: o.act_status||'计划中', meeting_link: o.act_meeting_link||'',
          replay_link: o.act_replay_link||'', guests: o.act_guests||'', description: o.act_desc||''
        }));

        // Resources
        const extR = collectItems('builder-ext', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
        const txtM = collectItems('builder-txt', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
        const filmR = collectItems('builder-film', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
        const otherR = collectItems('builder-other', ['res_title','res_url','res_desc']).map(o => ({ title: o.res_title||'', url: o.res_url||'', description: o.res_desc||'' }));
        data.resources = { extended_reading: extR, text_materials: txtM, film_resources: filmR, other: otherR };

        // Chatsubstance
        data.chatsubstance = JSON.stringify(collectItems('builder-chats', ['chat_topic','chat_speaker','chat_content']).map(o => ({
          topic: o.chat_topic||'', speaker: o.chat_speaker||'', content: o.chat_content||''
        })));

        // Serialize reading_schedule from form fields
        data.reading_schedule = JSON.stringify({
          summary: data.schedule_summary || '',
          pdf_url: data.schedule_pdf_url || ''
        });
        delete data.schedule_summary; delete data.schedule_pdf_url;

        // Clean up — remove builder field names not in books table
        delete data.online_activities; delete data.meeting_replays; delete data.isbn; delete data.page_count;
        ['edn_name','edn_translator','edn_publisher','edn_pros','edn_cons','edn_buy_link','edn_douban_link',
         'act_type','act_title','act_time','act_status','act_meeting_link','act_replay_link','act_guests','act_desc',
         'chat_topic','chat_speaker','chat_content',
         'res_title','res_url','res_desc'].forEach(f => delete data[f]);
        data.word_count = data.word_count ? parseInt(data.word_count) : null;
        saveBook(data, data.book_id);
        modal.remove();
        document.removeEventListener('submit', bookFormHandler);
      }
    }

    async function saveBook(data, id) {
      const payload = { ...data };
      delete payload.book_id;
      payload.updated_at = new Date().toISOString();
      if (!id) payload.created_by = store.get('user').id;

      let error;
      if (id) {
        ({ error } = await sb.from('books').update(payload).eq('id', id));
      } else {
        ({ error } = await sb.from('books').insert(payload));
      }
      if (error) { toast('保存失败：' + error.message, 'error'); return; }
      toast(id ? '书籍已更新' : '书籍已添加');
      router.render();
    }

    async function deleteBook(id) {
      if (!confirm('确定要删除这本书吗？')) return;
      const { error } = await sb.from('books').delete().eq('id', id);
      if (error) { toast('删除失败：' + error.message, 'error'); return; }
      toast('书籍已删除');
      router.render();
    }

    // Admin: add/edit event form
    function showEventForm(eventData = null) {
      const isEdit = !!eventData;
      const ev = eventData || { title:'', category:'', link:'', poster_url:'', location:'', event_date:'', guests:'', price:'', description:'', status:'upcoming' };
      const formHtml = `
        <form id="event-edit-form">
          <div class="form-group"><label>活动名称 *</label><input type="text" name="title" value="${esc(ev.title)}" required></div>
          <div class="form-group"><label>活动分类 *</label><select name="category" required>
            <option value="">请选择</option>
            <option value="文学高速" ${ev.category === '文学高速' ? 'selected' : ''}>文学高速</option>
            <option value="其他" ${ev.category === '其他' ? 'selected' : ''}>其他</option>
          </select></div>
          <div class="form-group"><label>活动链接</label><input type="url" name="link" value="${esc(ev.link || '')}" placeholder="https://...（可选）"></div>
          <div class="form-group">
            <label>海报图</label>
            <div class="cover-upload">
              <div class="cover-preview" id="poster-preview">
                ${ev.poster_url ? `<img src="${safeUrl(ev.poster_url)}" alt="">` : '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>'}
              </div>
              <div class="cover-inputs">
                <input type="url" name="poster_url" value="${esc(ev.poster_url || '')}" placeholder="粘贴图片 URL" id="poster-url-input" required>
                <div class="divider-text">或</div>
                <input type="file" accept="image/*" id="poster-file-input" style="font-size:0.85rem;">
              </div>
            </div>
          </div>
          <div class="form-group"><label>地点</label><input type="text" name="location" value="${esc(ev.location || '')}"></div>
          <div class="form-group"><label>时间</label><input type="datetime-local" name="event_date" value="${esc(ev.event_date ? dayjs(ev.event_date).format('YYYY-MM-DDTHH:mm') : '')}"></div>
          <div class="form-group"><label>嘉宾</label><input type="text" name="guests" value="${esc(ev.guests || '')}"></div>
          <div class="form-group"><label>价格</label><input type="text" name="price" value="${esc(ev.price || '')}" placeholder="免费 / ¥68"></div>
          <div class="form-group"><label>状态</label><select name="status">
            <option value="upcoming" ${ev.status === 'upcoming' ? 'selected' : ''}>即将开始</option>
            <option value="ongoing" ${ev.status === 'ongoing' ? 'selected' : ''}>进行中</option>
            <option value="ended" ${ev.status === 'ended' ? 'selected' : ''}>已结束</option>
            <option value="cancelled" ${ev.status === 'cancelled' ? 'selected' : ''}>已取消</option>
          </select></div>
          <div class="form-group"><label>活动简介（Markdown）</label><textarea name="description" style="min-height:100px;">${h(ev.description || '')}</textarea></div>
          <button type="submit" class="btn btn-primary">${isEdit ? '保存修改' : '添加活动'}</button>
          <input type="hidden" name="event_id" value="${esc(ev.id || '')}">
        </form>`;
      const modal = showModal(isEdit ? '编辑活动' : '添加活动', formHtml, () => {
        document.removeEventListener('submit', eventFormHandler);
      });
      document.addEventListener('submit', eventFormHandler);
      function eventFormHandler(e) {
        if (e.target.id !== 'event-edit-form') return;
        e.preventDefault();
        const fd = new FormData(e.target);
        const data = Object.fromEntries(fd.entries());
        saveEvent(data, data.event_id);
        modal.remove();
        document.removeEventListener('submit', eventFormHandler);
      }
    }

    async function saveEvent(data, id) {
      const payload = { ...data };
      delete payload.event_id;
      payload.updated_at = new Date().toISOString();
      if (!id) payload.created_by = store.get('user').id;

      let error;
      if (id) {
        ({ error } = await sb.from('events').update(payload).eq('id', id));
      } else {
        ({ error } = await sb.from('events').insert(payload));
      }
      if (error) { toast('保存失败：' + error.message, 'error'); return; }
      toast(id ? '活动已更新' : '活动已添加');
      router.render();
    }

    async function deleteEvent(id) {
      if (!confirm('确定要删除这个活动吗？')) return;
      const { error } = await sb.from('events').delete().eq('id', id);
      if (error) { toast('删除失败：' + error.message, 'error'); return; }
      toast('活动已删除');
      router.render();
    }

    // Admin button handlers
    document.addEventListener('click', async (e) => {
      // This handler is async because of AI fill button
      const addBookBtn = e.target.closest('#btn-add-book, #btn-add-book2');
      if (addBookBtn) { showBookForm(); return; }
      const addEventBtn = e.target.closest('#btn-add-event');
      if (addEventBtn) { showEventForm(); return; }
      const editBookBtn = e.target.closest('.btn-edit-book');
      if (editBookBtn) {
        const id = editBookBtn.dataset.id;
        const book = store.get('books').find(b => String(b.id) === id);
        if (book) showBookForm(book);
        return;
      }
      const delBookBtn = e.target.closest('.btn-del-book');
      if (delBookBtn) { deleteBook(delBookBtn.dataset.id); return; }
      const editEventBtn = e.target.closest('.btn-edit-event');
      if (editEventBtn) {
        const id = editEventBtn.dataset.id;
        const event = store.get('events').find(ev => String(ev.id) === id);
        if (event) showEventForm(event);
        return;
      }
      const delEventBtn = e.target.closest('.btn-del-event');
      if (delEventBtn) { deleteEvent(delEventBtn.dataset.id); return; }

      // Visual builder: add buttons
      const addBtn = e.target.closest('.btn-add-row');
      if (addBtn) {
        const action = addBtn.dataset.action;
        const map = {
          'add-edition':  { container: 'builder-editions', html: ednItem() },
          'add-activity': { container: 'builder-acts', html: actItem() },
          'add-ext':      { container: 'builder-ext', html: resItem() },
          'add-txt':      { container: 'builder-txt', html: resItem() },
          'add-film':     { container: 'builder-film', html: resItem() },
          'add-other':    { container: 'builder-other', html: resItem() },
          'add-chat':     { container: 'builder-chats', html: chatItem() }
        };
        const cfg = map[action];
        if (cfg) {
          const container = document.getElementById(cfg.container);
          if (container) {
            // Remove empty placeholder
            const placeholder = container.querySelector('.builder-item[style]');
            if (placeholder) placeholder.remove();
            container.insertAdjacentHTML('beforeend', cfg.html);
          }
        }
        return;
      }

      // AI fill button in book form
      const aiBtn = e.target.closest('#btn-ai-fill');
      if (aiBtn) {
        aiBtn.disabled = true;
        aiBtn.textContent = '⏳ AI 正在搜索编写...';
        const modal = aiBtn.closest('.modal');
        const titleEl = modal?.querySelector('[name="title"]');
        const authorEl = modal?.querySelector('[name="author"]');
        const descEl = modal?.querySelector('[name="description"]');
        const bioEl = modal?.querySelector('[name="author_bio"]');
        const ctxEl = modal?.querySelector('[name="historical_context"]');
        const result = await aiFillBookInfo(titleEl?.value || '', authorEl?.value || '');
        if (result) {
          if (descEl) descEl.value = result.description || '';
          if (bioEl) bioEl.value = result.author_bio || '';
          if (ctxEl) ctxEl.value = result.historical_context || '';
          toast('AI 内容已填充，请检查修改 ✨');
        }
        aiBtn.disabled = false;
        aiBtn.textContent = '🤖 AI 自动填充简介';
        return;
      }
    });

    // ===========================================
    // NEW BOOKS — 新书速递交互
    // ===========================================
    document.addEventListener('click', async (e) => {
      // Toggle wishlist vote
      const wishBtn = e.target.closest('[data-action="toggle-wish"]');
      if (wishBtn) {
        e.preventDefault();
        const user = store.get('user');
        if (!user) {
          toast('请先登录', 'error');
          router.navigate('/login?redirect=' + encodeURIComponent('/new-books'));
          return;
        }
        const bookId = parseInt(wishBtn.dataset.bookId);
        const isActive = wishBtn.classList.contains('active');

        wishBtn.disabled = true;
        try {
          if (isActive) {
            const { error } = await sb.from('reading_wishlist')
              .delete().eq('user_id', user.id).eq('book_id', bookId);
            if (error) throw error;
            toast('已取消想共读');
          } else {
            const { error } = await sb.from('reading_wishlist')
              .insert({ user_id: user.id, book_id: bookId });
            if (error) {
              if (error.code === '23505') { toast('你已经标记过了', 'error'); }
              else throw error;
            } else {
              toast('已标记想共读 ❤️');
            }
          }
          router.render();
        } catch (err) {
          toast('操作失败：' + (err.message || '未知错误'), 'error');
        }
        wishBtn.disabled = false;
        return;
      }

      // Manual refresh button
      const refreshBtn = e.target.closest('#btn-refresh-books');
      if (refreshBtn) {
        e.preventDefault();
        if (!store.get('isAdmin')) {
          toast('只有管理员可以同步新书数据', 'error');
          return;
        }
        const { data: { session } } = await sb.auth.getSession();
        if (!session) {
          toast('请先登录管理员账号', 'error');
          router.navigate('/login?redirect=' + encodeURIComponent('/new-books'));
          return;
        }
        refreshBtn.disabled = true;
        refreshBtn.innerHTML = '<i data-lucide="refresh-cw" style="width:14px;height:14px;"></i> 同步中...';
        lucide.createIcons();
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/scrape-douban`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${session.access_token}`
            },
            body: JSON.stringify({ force: true })
          });
          const result = await resp.json();
          if (result.success) {
            toast(`同步完成，获取 ${result.count} 本新书`);
          } else if (result.cached) {
            toast('数据已在 24 小时内更新过，无需重复同步');
          } else {
            toast('同步失败：' + (result.error || '未知错误'), 'error');
          }
        } catch (err) {
          toast('同步请求失败，请检查网络后重试', 'error');
        }
        router.render();
        return;
      }
    });

    // ===========================================
    // LATIN AMERICA MAP — 西语文学地图交互 (Leaflet + GeoJSON)
    // ===========================================
    let _latamMap = null;
    let _latamLayer = null;

    function renderLatamPanel(countryId) {
      const panel = document.getElementById('latam-panel');
      if (!panel) { console.warn('latam-panel not found'); return; }
      try {
      // Update tag active states
      document.querySelectorAll('.latam-tag').forEach(t => t.classList.remove('active'));

      if (!countryId) {
        panel.innerHTML = `
          <h2>🌎 拉丁美洲文学地图</h2>
          <div class="panel-intro">
            拉丁美洲是二十世纪世界文学的爆炸原点。从魔幻现实主义到结构现实主义，
            从博尔赫斯的迷宫到聂鲁达的情诗，这片大陆孕育了最富想象力的文学图景。<br><br>
            <strong>点击地图上的国家</strong>，发现那些改变了世界文学版图的作家与作品。
          </div>
          <div style="margin-top:var(--space-3);padding-top:var(--space-3);border-top:1px solid var(--color-border);">
            <div style="font-size:0.78rem;color:var(--color-text-3);margin-bottom:6px;">🏆 诺贝尔文学奖得主（拉美）</div>
            <div style="font-size:0.78rem;color:var(--color-text-2);line-height:1.8;">
              1945 · 🇨🇱 加夫列拉·米斯特拉尔<br>
              1967 · 🇬🇹 米格尔·阿斯图里亚斯<br>
              1971 · 🇨🇱 巴勃罗·聂鲁达<br>
              1982 · 🇨🇴 加西亚·马尔克斯<br>
              1990 · 🇲🇽 奥克塔维奥·帕斯<br>
              2010 · 🇵🇪 巴尔加斯·略萨
            </div>
          </div>`;
        // Reset GeoJSON layer
        if (_latamLayer) {
          _latamLayer.eachLayer(function(l) { l._selected = false; l.setStyle({ fillColor: '#d9a87a', fillOpacity: 0.45, color: '#8b6914', weight: 1.5 }); });
        }
        return;
      }

      const country = LATAM_COUNTRIES.find(c => c.id === countryId);
      if (!country) return;

      // Highlight tag
      const tagEl = document.querySelector(`.latam-tag[data-country="${countryId}"]`);
      if (tagEl) tagEl.classList.add('active');

      // Highlight map feature
      if (_latamLayer) {
        _latamLayer.eachLayer(function(layer) {
          layer._selected = false;
          layer.setStyle({ fillColor: '#d9a87a', fillOpacity: 0.45, color: '#8b6914', weight: 1.5 });
        });
        _latamLayer.eachLayer(function(layer) {
          if (layer.feature && layer.feature.properties.id === countryId) {
            layer._selected = true;
            layer.setStyle({ fillColor: '#a46533', fillOpacity: 0.7, weight: 3, color: '#8b4a2a' });
            layer.bringToFront();
            if (layer._map) {
              layer._map.fitBounds(layer.getBounds(), { padding: [30,30], maxZoom: 6 });
            }
          }
        });
      }

      const authorsHtml = country.authors.map(a => `
        <div class="latam-author-card">
          <div class="author-name"><span class="icon">✍️</span>${h(a.name)}<span style="font-weight:400;font-size:0.75rem;color:var(--color-text-3);margin-left:4px;">${h(a.en)}</span></div>
          <div class="author-bio">${h(a.bio)}</div>
          <div class="author-works">${a.works.map(w => `<span class="work-tag">📖 ${h(w)}</span>`).join('')}</div>
        </div>
      `).join('');

      panel.innerHTML = `
        <h2>📍 ${h(country.name)}</h2>
        <div class="panel-intro">共 ${country.authors.length} 位代表作家</div>
        ${authorsHtml}
        <button class="btn btn-sm btn-outline" style="margin-top:var(--space-2);" onclick="renderLatamPanel(null);if(_latamLayer)_latamLayer.resetStyle();">← 返回总览</button>
      `;
      } catch (err) {
        console.error('renderLatamPanel error:', err);
        panel.innerHTML = '<p style="color:var(--color-danger);">出错了：' + err.message + '</p>';
      }
    }

    async function initLatamMap() {
      const mapEl = document.getElementById('latam-leaflet-map');
      if (!mapEl) return;

      // Load Leaflet + topojson dynamically (only when visiting this page)
      if (typeof L === 'undefined') {
        await Promise.all([
          new Promise((ok, fail) => { const l = document.createElement('link'); l.rel='stylesheet'; l.href='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css'; l.onload=ok; l.onerror=fail; document.head.appendChild(l); }),
          new Promise((ok, fail) => { const s = document.createElement('script'); s.src='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.js'; s.onload=ok; s.onerror=fail; document.head.appendChild(s); }),
          new Promise((ok, fail) => { const s = document.createElement('script'); s.src='https://cdn.jsdelivr.net/npm/topojson-client@3'; s.onload=ok; s.onerror=fail; document.head.appendChild(s); })
        ]);
        await new Promise(r => setTimeout(r, 100)); // wait for globals to settle
      }

      // Destroy existing map instance
      if (_latamMap) { _latamMap.remove(); _latamMap = null; _latamLayer = null; }

      // Create Leaflet map centered on Latin America
      _latamMap = L.map(mapEl, {
        center: [-15, -65],
        zoom: 3,
        minZoom: 3,
        maxZoom: 8,
        zoomControl: true,
        scrollWheelZoom: true,
        maxBounds: [[15, -120], [-60, -30]],
        maxBoundsViscosity: 0.5
      });

      // Light basemap (CartoDB)
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>',
        subdomains: 'abcd',
        maxZoom: 19
      }).addTo(_latamMap);

      // Fetch real country boundaries from Natural Earth (TopoJSON → GeoJSON)
      const isoNumSet = new Set(LATAM_COUNTRIES.map(c => c.isoNum));
      try {
        const resp = await fetch('https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json');
        if (!resp.ok) throw new Error('TopoJSON fetch failed');
        const world = await resp.json();
        // topojson-client global: topojson
        const topo = window.topojson || globalThis.topojson;
        if (!topo) throw new Error('topojson-client not loaded');
        const geojson = topo.feature(world, world.objects.countries);
        // Filter to Latin America and attach our metadata
        geojson.features = geojson.features
          .filter(f => isoNumSet.has(parseInt(f.id, 10)))
          .map(f => {
            const c = LATAM_COUNTRIES.find(function(x) { return x.isoNum === parseInt(f.id, 10); });
            if (c) { f.properties = { id: c.id, name: c.name, authors: c.authors }; }
            return f;
          });

        // GeoJSON layer
        const defaultStyle = { fillColor: '#d9a87a', fillOpacity: 0.45, color: '#8b6914', weight: 1.5, opacity: 0.8 };

        _latamLayer = L.geoJSON(geojson, {
          style: function() { return defaultStyle; },
          onEachFeature: function(feature, layer) {
            layer.on({
              mouseover: function(e) {
                const lyr = e.target;
                if (!lyr._selected) {
                  lyr.setStyle({ fillColor: '#c17d4b', fillOpacity: 0.7, weight: 2.5, color: '#6b3a1f' });
                }
                lyr.bringToFront();
              },
              mouseout: function(e) {
                const lyr = e.target;
                if (!lyr._selected) {
                  lyr.setStyle(defaultStyle);
                }
              },
              click: function(e) {
                _latamLayer.eachLayer(function(l) { l._selected = false; l.setStyle({ fillColor: '#d9a87a', fillOpacity: 0.45, color: '#8b6914', weight: 1.5 }); });
                e.target._selected = true;
                e.target.setStyle({ fillColor: '#a46533', fillOpacity: 0.7, weight: 3, color: '#8b4a2a' });

                const props = feature.properties;
                const panel = document.getElementById('latam-panel');
                if (panel && props && props.authors) {
                  document.querySelectorAll('.latam-tag').forEach(t => t.classList.remove('active'));
                  const tag = document.querySelector('.latam-tag[data-country="'+props.id+'"]');
                  if (tag) tag.classList.add('active');
                  var html = '<h2>\u{1F4CD} '+h(props.name)+'</h2><div class="panel-intro">共 '+props.authors.length+' 位代表作家</div>';
                  for (var i = 0; i < props.authors.length; i++) {
                    var a = props.authors[i];
                    html += '<div class="latam-author-card"><div class="author-name"><span class="icon">✍️</span>'+h(a.name)+'<span style="font-weight:400;font-size:0.75rem;color:#a09588;margin-left:4px;">'+h(a.en)+'</span></div><div class="author-bio">'+h(a.bio)+'</div><div class="author-works">';
                    for (var j = 0; j < a.works.length; j++) { html += '<span class="work-tag">\u{1F4D6} '+h(a.works[j])+'</span>'; }
                    html += '</div></div>';
                  }
                  html += '<button class="btn btn-sm btn-outline" style="margin-top:var(--space-2);" id="btn-latam-back">← 返回总览</button>';
                  panel.innerHTML = html;
                  document.getElementById('btn-latam-back')?.addEventListener('click', function() {
                    renderLatamPanel(null);
                  });
                }
              }
            });
          }
        }).addTo(_latamMap);
      } catch (err) {
        console.error('Failed to load map data:', err);
        mapEl.innerHTML = '<div style="padding:20px;text-align:center;color:var(--color-danger);">地图数据加载失败：' + (err.message || '未知错误') + '<br><small>请检查网络后刷新重试</small></div>';
      }
    }

    // Country tag click handler
    document.addEventListener('click', (e) => {
      const countryTag = e.target.closest('.latam-tag');
      if (countryTag) {
        const countryId = countryTag.dataset.country;
        if (_latamLayer) {
          let found = false;
          _latamLayer.eachLayer(function(layer) {
            if (layer.feature && layer.feature.properties.id === countryId) {
              found = true;
              layer.fire('click');
            }
          });
          if (!found) renderLatamPanel(countryId);
        } else {
          renderLatamPanel(countryId);
        }
        return;
      }
    });

    // ===========================================
    // COVER UPLOAD — safe DOM, no innerHTML
    // ===========================================
    function updateCoverPreview(url) {
      const preview = document.getElementById('cover-preview');
      if (!preview) return;
      preview.innerHTML = '';
      if (url) {
        const img = document.createElement('img');
        img.src = url; img.alt = ''; img.onerror = () => { preview.textContent = '?'; };
        preview.appendChild(img);
      } else {
        preview.innerHTML = '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>';
        lucide.createIcons();
      }
    }
    document.addEventListener('input', (e) => {
      if (e.target.id === 'cover-url-input') updateCoverPreview(e.target.value);
    });
    document.addEventListener('change', async (e) => {
      if (e.target.id !== 'cover-file-input') return;
      const file = e.target.files[0];
      if (!file) return;
      const ext = file.name.split('.').pop();
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '').replace(/\.+/g, '.') || 'cover';
      const path = `${Date.now()}_${safeName}.${ext}`;
      const { data, error } = await sb.storage.from('covers').upload(path, file);
      if (error) { toast('封面上传失败：' + error.message, 'error'); return; }
      const { data: { publicUrl } } = sb.storage.from('covers').getPublicUrl(path);
      const urlInput = document.getElementById('cover-url-input');
      if (urlInput) urlInput.value = publicUrl;
      updateCoverPreview(publicUrl);
      toast('封面上传成功');
    });

    // Poster upload for events
    function updatePosterPreview(url) {
      const preview = document.getElementById('poster-preview');
      if (!preview) return;
      preview.innerHTML = '';
      if (url) {
        const img = document.createElement('img');
        img.src = url; img.alt = ''; img.onerror = () => { preview.textContent = '?'; };
        preview.appendChild(img);
      } else {
        preview.innerHTML = '<i data-lucide="image" style="width:28px;height:28px;color:var(--color-text-3);"></i>';
        lucide.createIcons();
      }
    }
    document.addEventListener('input', (e) => {
      if (e.target.id === 'poster-url-input') updatePosterPreview(e.target.value);
    });
    document.addEventListener('change', async (e) => {
      if (e.target.id !== 'poster-file-input') return;
      const file = e.target.files[0];
      if (!file) return;
      const ext = file.name.split('.').pop();
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '').replace(/\.+/g, '.') || 'poster';
      const path = `${Date.now()}_${safeName}.${ext}`;
      const { data, error } = await sb.storage.from('covers').upload(path, file);
      if (error) { toast('海报上传失败：' + error.message, 'error'); return; }
      const { data: { publicUrl } } = sb.storage.from('covers').getPublicUrl(path);
      const urlInput = document.getElementById('poster-url-input');
      if (urlInput) urlInput.value = publicUrl;
      updatePosterPreview(publicUrl);
      toast('海报上传成功');
    });

    // PDF upload for reading schedule
    document.addEventListener('change', async (e) => {
      if (e.target.id !== 'schedule-pdf-input') return;
      const file = e.target.files[0];
      if (!file) return;
      const ext = file.name.split('.').pop();
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '').replace(/\.+/g, '.') || 'schedule';
      const path = `${Date.now()}_${safeName}.${ext}`;
      const { data, error } = await sb.storage.from('files').upload(path, file);
      if (error) { toast('PDF 上传失败：' + error.message, 'error'); return; }
      const { data: { publicUrl } } = sb.storage.from('files').getPublicUrl(path);
      const urlInput = document.getElementById('schedule-pdf-url');
      const nameEl = document.getElementById('schedule-pdf-name');
      if (urlInput) urlInput.value = publicUrl;
      if (nameEl) nameEl.textContent = '已上传：' + file.name;
      toast('PDF 上传成功');
    });

    // ===========================================
    // INIT
    // ===========================================
    async function init() {
      try {
        await initAuth();
      } catch (err) {
        console.error('Init error:', err);
      }
    }

    // Auth is initialized from the window load handler before the first route render.
