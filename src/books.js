import { renderBookCard, statusTag } from './components.js';
import { canViewResource, renderBookAccessPanel, renderProtectedGroup, renderProtectedLink, renderProtectedText, resourceKey } from './access.js';
import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';
import { GENRES } from './constants.js';
import { loadBooks } from './data.js';
import { route } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { loadBookAccessSummary } from './tickets.js';
import { esc, formatDate, h, isDoubanBookUrl, parseHttpUrl, proxyImg, safeMarked, safeUrl } from './utils.js';

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

const bookDetailState = new Map();

function lazyTabPlaceholder(label) {
  return `
    <div class="empty-state compact">
      <i data-lucide="loader"></i>
      <p>${h(label)}将在打开本分页时加载。</p>
    </div>
  `;
}

async function renderEditionTab(book) {
  let editions = [];
  try { editions = typeof book.edition_guide === 'string' ? JSON.parse(book.edition_guide || '[]') : (book.edition_guide || []); } catch(e){}

  const editionCoverCache = {};
  const editionDoubanUrls = editions.filter(e => isDoubanBookUrl(e.douban_link)).map(e => e.douban_link);
  if (editionDoubanUrls.length > 0) {
    try {
      const { data: cached } = await sb.from('douban_book_cache').select('*').in('douban_url', editionDoubanUrls);
      if (cached) cached.forEach(c => { editionCoverCache[c.douban_url] = c; });
    } catch(e) {}
    const uncached = editionDoubanUrls.filter(url => !editionCoverCache[url]);
    if (uncached.length > 0) {
      const results = await Promise.allSettled(uncached.map(url =>
        fetch(`${SUPABASE_URL}/functions/v1/fetch-douban-book`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${SUPABASE_ANON_KEY}` },
          body: JSON.stringify({ url })
        }).then(r => r.json()).then(r => (r && r.success) ? r.data : null).catch(() => null)
      ));
      results.forEach((r, i) => {
        if (r.status === 'fulfilled' && r.value) editionCoverCache[uncached[i]] = r.value;
      });
    }
  }

  const editionNotesHtml = safeMarked(book.edition_notes || '');
  const editionsCardsHtml = editions.length === 0 ? '<p style="color:var(--color-text-3);">暂无版本建议。</p>' : `
    <div style="display:flex;flex-direction:column;gap:var(--space-2);">
      ${editions.map(e => {
        const db = e.douban_link ? editionCoverCache[e.douban_link] : null;
        const coverHtml = db?.cover_url ? `<div class="edition-cover"><img src="${esc(proxyImg(db.cover_url))}" alt="${esc(db.title || '')}" loading="lazy"></div>` : '';
        return `
        <div class="edition-card ${coverHtml ? 'edition-card-with-cover' : ''}">
          <div class="edition-card-body">
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
          ${coverHtml}
        </div>
      `;}).join('')}
    </div>`;

  return `
    ${book.edition_notes ? `<div class="md-content" style="max-width:none;margin-bottom:var(--space-4);">${editionNotesHtml}</div>` : ''}
    ${editionsCardsHtml}`;
}

async function renderResourcesTab(book, accessSummary) {
  let resources = { extended_reading: [], text_materials: [], film_resources: [], other: [] };
  try { resources = typeof book.resources === 'string' ? JSON.parse(book.resources) : (book.resources || {}); } catch(e) {}

  const extItems = resources.extended_reading || [];
  const extReadingKey = resourceKey(book.id, 'resource_extended_reading', 'all', 'list');
  const extReadingUnlocked = canViewResource(accessSummary, extReadingKey);
  const doubanCache = {};
  const doubanUrls = extReadingUnlocked ? extItems.filter(item => isDoubanBookUrl(item.url)).map(item => item.url) : [];
  if (doubanUrls.length > 0) {
    try {
      const { data: cached } = await sb.from('douban_book_cache').select('*').in('douban_url', doubanUrls);
      if (cached) cached.forEach(c => { doubanCache[c.douban_url] = c; });
    } catch(e) {}
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

  const extReadingHtml = extItems.length === 0 ? '' : `
    <div class="extended-reading-section">
      <h4>延伸读物</h4>
      ${extReadingUnlocked ? `
        <div class="extended-reading-grid">
          ${extItems.map((item) => {
          const db = doubanCache[item.url] || {};
          return `
          <div class="new-book-card extended-reading-card">
            <div class="nb-cover" style="width:100px;">
              ${db.cover_url
                ? `<img src="${esc(proxyImg(db.cover_url))}" alt="" loading="lazy" onerror="this.style.display='none';this.nextElementSibling.style.display='block';">`
                : ''}
              <i data-lucide="book" class="cover-fallback" style="${db.cover_url ? 'display:none;' : ''}"></i>
            </div>
            <div class="nb-body extended-reading-body">
              <div class="extended-reading-copy">
                <h3>${h(db.title || item.title)}</h3>
                ${db.author ? `<div class="nb-row"><span class="nb-label">作者</span>${h(db.author)}</div>` : ''}
                ${db.publisher ? `<div class="nb-row"><span class="nb-label">出版方</span>${h(db.publisher)}</div>` : ''}
                ${db.rating ? `<div class="nb-row rating">⭐${h(db.rating)} · ${db.review_count || 0}人评价</div>` : ''}
                ${item.description ? `<div class="nb-row extended-reading-description">${h(item.description)}</div>` : ''}
              </div>
              ${item.url ? `<a href="${safeUrl(item.url)}" target="_blank" rel="noopener" class="btn btn-outline btn-sm extended-reading-detail">查看详情</a>` : ''}
            </div>
          </div>`;
          }).join('')}
        </div>
      ` : renderProtectedGroup({
        bookId: book.id,
        key: extReadingKey,
        title: '延伸读物暂未解锁',
        description: `本期共读列出了 ${extItems.length} 本延伸读物。解锁后可查看完整书单、作者、封面和详情链接。`,
        summary: accessSummary,
        unlockLabel: '解锁延伸读物'
      })}
    </div>`;

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
        ${items.map((item, index) => `
          <div style="padding:6px 0;border-bottom:1px solid var(--color-border);display:flex;justify-content:space-between;align-items:center;gap:var(--space-2);">
            <div>
              <span>${h(item.title)}</span>
              ${item.description ? `<div style="font-size:0.84rem;color:var(--color-text-3);margin-top:2px;">${h(item.description)}</div>` : ''}
            </div>
            ${renderProtectedLink({
              bookId: book.id,
              key: resourceKey(book.id, `resource_${sec.key}`, index, 'url'),
              url: item.url,
              label: '查看',
              summary: accessSummary
            })}
          </div>
        `).join('')}
      </div>
    </div>`;
  }).join('');

  return resourcesHtml || '<p style="color:var(--color-text-3);">暂无资源材料。</p>';
}

async function loadBookLazyTab(target) {
  if (!target?.dataset.lazyBookTab || target.dataset.loaded === 'true') return;
  const state = bookDetailState.get(target.dataset.bookId);
  if (!state) return;

  const tabName = target.dataset.lazyBookTab;
  target.innerHTML = '<div class="empty-state compact"><i data-lucide="loader"></i><p>正在加载...</p></div>';
  lucide.createIcons();

  try {
    if (tabName === 'edition') {
      target.innerHTML = await renderEditionTab(state.book);
    } else if (tabName === 'resources') {
      target.innerHTML = await renderResourcesTab(state.book, state.accessSummary);
    }
    target.dataset.loaded = 'true';
  } catch (err) {
    console.warn('Book lazy tab load failed:', err);
    target.innerHTML = '<div class="empty-state"><i data-lucide="alert-triangle"></i><p>加载失败，请稍后重试。</p></div>';
  }
  lucide.createIcons();
}

// ===========================================
// ROUTE: BOOK DETAIL (v2)
// ===========================================
route('/books/:id', async (params) => {
  // Check memory cache first (hit if user visited book list before)
  const cachedBook = store.get('books').find(b => b.id == params.id);
  const bookPromise = cachedBook
    ? Promise.resolve(cachedBook)
    : sb.from('books').select('*').eq('id', params.id).single().then(({ data }) => data);
  const accessPromise = loadBookAccessSummary(params.id);
  const [book, accessSummary] = await Promise.all([bookPromise, accessPromise]);
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

  // Tab 3: 版本建议 — 延迟到用户打开分页时加载，避免阻塞首屏
  const editionsHtml = lazyTabPlaceholder('版本建议');

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
      ${activities.map((a, index) => `
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
            ${renderProtectedLink({
              bookId: book.id,
              key: resourceKey(book.id, 'activity', index, 'meeting_link'),
              url: a.meeting_link,
              label: '活动链接',
              summary: accessSummary
            })}
            ${renderProtectedLink({
              bookId: book.id,
              key: resourceKey(book.id, 'activity', index, 'replay_link'),
              url: a.replay_link,
              label: '回放回顾',
              summary: accessSummary
            })}
            ${!a.meeting_link && !a.replay_link && a.status === '计划中' ? '<span style="font-size:0.82rem;color:var(--color-text-3);">积极筹备中，敬请期待</span>' : ''}
          </div>
        </div>
      `).join('')}
    </div>`;

  // Tab 6: 资源材料 — 延迟到用户打开分页时加载，避免阻塞首屏
  const resourcesHtml = lazyTabPlaceholder('资源材料');

  // Tab 7: 聊天干货
  let chats = [];
  try { chats = typeof book.chatsubstance === 'string' ? JSON.parse(book.chatsubstance||'[]') : (book.chatsubstance||[]); } catch(e){}
  const chatsHtml = chats.length === 0 ? '<p style="color:var(--color-text-3);">暂无聊天干货。</p>' : `
    <div style="display:flex;flex-direction:column;gap:var(--space-3);">
      ${chats.map((c, index) => `
        <div class="edition-card">
          <h3 style="margin-bottom:var(--space-1);">${c.topic || '干货主题'}</h3>
          <div style="font-size:0.88rem;color:var(--color-text-2);margin-bottom:var(--space-2);">主发言人：${c.speaker || '未知'}</div>
          ${renderProtectedText({
            bookId: book.id,
            key: resourceKey(book.id, 'chat', index, 'content'),
            markdown: c.content,
            summary: accessSummary
          })}
        </div>
      `).join('')}
    </div>`;

  const joinEnabled = !!book.join_enabled || !!book.join_qr_url;
  const joinHtml = `
    <div class="book-join-flow">
      <section class="book-join-step">
        <div class="book-join-step-copy">
          <span>01</span>
          <p>欢迎加入本期共读，请在二维码有效期内扫码入群，逾期将无法加入。</p>
        </div>
        <div class="book-join-step-action">
          ${book.join_qr_url ? `
            <div class="book-join-qr">
              <img src="${safeUrl(book.join_qr_url)}" alt="共读群二维码">
              <p>扫码加入本期共读群</p>
            </div>
          ` : '<div class="book-join-placeholder"><i data-lucide="qr-code"></i><strong>二维码暂未上传</strong><p>请等待管理员补充入群二维码。</p></div>'}
        </div>
      </section>

      <section class="book-join-step">
        <div class="book-join-step-copy">
          <span>02</span>
          <p>入群后在群公告中获取共读密码，并在此页核销以解锁共读权益（本期共读全部资源），系统将同步发放纪念徽章。</p>
        </div>
        <div class="book-join-step-action">
          <form class="book-claim-form" data-action="claim-co-reading-password">
            <input type="hidden" name="book_id" value="${h(book.id)}">
            <div class="form-group">
              <label>群内 ID / 昵称</label>
              <input type="text" name="group_member_id" required placeholder="用于管理员核对入群身份">
            </div>
            <div class="form-group">
              <label>共读密码</label>
              <input type="password" name="password" required placeholder="请输入群内提供的密码">
            </div>
            ${store.get('user')
              ? '<button type="submit" class="btn btn-primary">核销共读密码</button>'
              : `<a href="#/login?redirect=/books/${h(book.id)}" class="btn btn-primary">登录后核销</a>`}
          </form>
        </div>
      </section>

      <section class="book-join-step">
        <div class="book-join-step-copy">
          <span>03</span>
          <p>当您完成本期阅读后，点击以下按钮发布已读书友圈，纪念徽章将升级为已读版。发布时间不做限制，你可以在任何时间完成，读完就好。</p>
        </div>
        <div class="book-join-step-action">
          <button
            type="button"
            class="btn btn-outline book-join-finished-btn"
            data-action="open-reading-post-composer"
            data-linked-book-id="${h(book.id)}"
            data-book-title="${esc(book.title)}"
            data-author="${esc(book.author || '')}"
            data-cover-url="${esc(book.cover_url || '')}"
            data-post-type="finished"
          >
            <i data-lucide="square-pen"></i> 发布已读动态
          </button>
        </div>
      </section>
    </div>
  `;

  bookDetailState.set(String(book.id), { book, accessSummary });

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
        ${joinEnabled ? '<button class="tab" data-tab="join">加入我们</button>' : ''}
        <button class="tab" data-tab="activities">活动安排</button>
        <button class="tab" data-tab="resources">资源材料</button>
        <button class="tab" data-tab="chats">聊天干货</button>
      </div>

      ${renderBookAccessPanel(book, accessSummary)}

      <div id="tab-intro" class="tab-content">${introHtml}</div>
      <div id="tab-host" class="tab-content" style="display:none;">${hostTabHtml}</div>
      ${hostNotesTabContent}
      <div id="tab-edition" class="tab-content" style="display:none;" data-lazy-book-tab="edition" data-book-id="${h(book.id)}">${editionsHtml}</div>
      <div id="tab-schedule" class="tab-content" style="display:none;">${scheduleHtml}</div>
      ${joinEnabled ? `<div id="tab-join" class="tab-content" style="display:none;">${joinHtml}</div>` : ''}
      <div id="tab-activities" class="tab-content" style="display:none;">${activitiesHtml}</div>
      <div id="tab-resources" class="tab-content" style="display:none;" data-lazy-book-tab="resources" data-book-id="${h(book.id)}">
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
  if (target) {
    target.style.display = '';
    loadBookLazyTab(target);
  }
});
