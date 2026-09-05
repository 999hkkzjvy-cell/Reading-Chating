import { bindNotificationEvents, getAuthRedirectRoute, initAuth, replaceAuthRedirectRoute } from './auth.js';
import { bindAccessEvents } from './access.js';
import './admin.js';
import './books.js?v=pwa-20260818-6';
import { bindAuthEvents, registerAuthRoutes } from './authPages.js';
import { initPuzzleCaptcha, refreshCaptcha } from './captcha.js';
import { renderHomeBookCard } from './components.js';
import {
  loadBooks,
  loadConfig,
  loadEvents,
  loadHomeBooks,
} from './data.js';
import './events.js';
import { bindLatamEvents, initLatamMap, renderLatamPage } from './latam.js';
import { bindMemberCenterEvents, registerMemberCenterRoutes } from './memberCenter.js?v=pwa-20260818-7';
import { registerMemberSystemInfoRoutes } from './memberSystemInfo.js';
import './newBooks.js?v=pwa-20260818-6';
import { bindProfileEvents, registerProfileRoutes } from './profile.js?v=pwa-20260818-7';
import { bindReadingPostEvents, registerReadingPostRoutes } from './readingPosts.js?v=reading-tags-20260821-1';
import { initPwaShell, syncPwaShell } from './pwaShell.js?v=pwa-20260818-2';
import { applyPwaMode, isPwaMobile } from './pwaMode.js';
import { registerPwaServiceWorker } from './pwaServiceWorker.js?v=pwa-20260818-1';
import { route, router, setAfterRouteRender } from './router.js';
import { store } from './store.js';
import { bindUploadHandlers } from './uploads.js';
import { safeMarked } from './utils.js';

applyPwaMode();
registerPwaServiceWorker();

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

    setAfterRouteRender((path) => {
      lucide.createIcons();
      initPuzzleCaptcha();
      if (document.getElementById('latam-leaflet-map')) {
        setTimeout(() => initLatamMap(), 50);
      }
      router.updateNav(path);
      bindGlobalEvents();
      syncPwaShell(path);
    });

    window.addEventListener('hashchange', () => router.render());
    window.addEventListener('password-recovery-started', () => {
      replaceAuthRedirectRoute('/reset-password');
      router.render();
    });
    window.addEventListener('load', async () => {
      initPwaShell();
      bindGlobalEvents();
      const pendingAuthRedirect = getAuthRedirectRoute();
      await init();
      const authRedirect = pendingAuthRedirect || getAuthRedirectRoute();
      if (authRedirect) {
        replaceAuthRedirectRoute(authRedirect);
      }
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

    registerAuthRoutes();
    registerMemberCenterRoutes();
    registerMemberSystemInfoRoutes();
    registerReadingPostRoutes();

    // ===========================================
    // ROUTE: HOME
    // ===========================================
    route('/', async () => {
      const [config, latestBooks] = await Promise.all([
        loadConfig(),
        loadHomeBooks()
      ]);

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
        <div data-pwa-page="home">
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
            <a href="#/member-system" class="home-member-system-link">
              <span><i data-lucide="badge-help"></i> 会员积分、票券与徽章系统说明</span>
              <i data-lucide="chevron-right"></i>
            </a>
          </div>
        </section>
        <section class="section" style="background:var(--color-bg-alt);">
          <div class="container" style="text-align:center;">
            <h2 style="margin-bottom:var(--space-2);">加入我们</h2>
            <p style="color:var(--color-text-2);margin-bottom:var(--space-3);">注册账号即可发布书友圈，记录你的阅读旅程。</p>
            ${store.get('user') ? '' : '<a href="#/register" class="btn btn-primary btn-lg">立即注册</a>'}
          </div>
        </section>
        </div>
      `;
    });

    route('/latin-america', (...args) => {
      if (isPwaMobile()) {
        return `
          <section class="section pwa-route-notice">
            <div class="container">
              <div class="card">
                <div class="card-body">
                  <i data-lucide="map" aria-hidden="true"></i>
                  <h2>西语文学专区暂请使用网页版</h2>
                  <p>移动端地图与专题内容正在完善中，当前先保留完整网页版体验。</p>
                  <a class="btn btn-primary" href="/?source=web#/latin-america" target="_blank" rel="noopener">打开网页版专区</a>
                </div>
              </div>
            </div>
          </section>
        `;
      }
      return renderLatamPage(...args);
    });

    registerProfileRoutes();

    // ===========================================
    // INIT
    // ===========================================
    async function init() {
      try {
        bindAuthEvents();
        bindProfileEvents();
        bindUploadHandlers();
        bindLatamEvents();
        bindMemberCenterEvents();
        bindReadingPostEvents();
        bindNotificationEvents();
        bindAccessEvents();
        await initAuth();
      } catch (err) {
        console.error('Init error:', err);
      }
    }

    // Auth is initialized from the window load handler before the first route render.
