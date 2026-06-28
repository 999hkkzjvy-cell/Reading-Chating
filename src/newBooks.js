import { SUPABASE_URL } from './config.js';
import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { esc, h, proxyImg, safeUrl } from './utils.js';

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

