import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';
import { MOODS } from './constants.js';
import { loadMemberSummary } from './members.js';
import { openBadgePreview } from './memberCenter.js';
import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { showModal, toast } from './ui.js';
import { esc, formatDateTime, h, isDoubanBookUrl, proxyImg, safeColor, safeUrl } from './utils.js';

const POST_TYPE_LABELS = {
  want: '想读',
  reading: '在读',
  finished: '已读'
};

const VISIBILITY_LABELS = {
  public: '公开',
  private: '仅自己可见'
};

const CALENDAR_DAY_NAMES = ['日', '一', '二', '三', '四', '五', '六'];

const postCache = new Map();

async function loadReadingPosts(scope = 'public') {
  const { data, error } = await sb.rpc('list_reading_posts', { p_scope: scope });
  if (error) {
    console.warn('Reading posts unavailable:', error.message);
    return { posts: [], error };
  }
  return { posts: data || [], error: null };
}

function postTypeOptions(selected = 'reading') {
  return Object.entries(POST_TYPE_LABELS).map(([value, label]) => (
    `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${h(label)}</option>`
  )).join('');
}

function visibilityOptions(selected = 'public') {
  return Object.entries(VISIBILITY_LABELS).map(([value, label]) => (
    `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${h(label)}</option>`
  )).join('');
}

function renderAuthorAvatar(post) {
  if (post.avatar_url) {
    return `<img src="${safeUrl(post.avatar_url)}" alt="">`;
  }
  return h((post.display_name || '书')[0].toUpperCase());
}

function formatBookTitle(title) {
  const clean = String(title || '').trim();
  if (!clean) return '';
  return /^《.*》$/.test(clean) ? clean : `《${clean.replace(/^《|》$/g, '')}》`;
}

function contentLabel(postType) {
  if (postType === 'finished') return '书评';
  return '感想';
}

function ratingEmoji(score) {
  const n = Number(score);
  if (isNaN(n)) return '';
  if (n < 0) return '💩';
  if (n < 6) return '🤢';
  if (n < 8) return '🙂';
  return '👏🏻';
}

function renderTextBlock(label, text, cls = '') {
  if (!text) return '';
  return `
    <div class="reading-post-content-block ${cls}">
      <span>${h(label)}</span>
      <p class="reading-post-content">${h(text)}</p>
    </div>
  `;
}

function renderPostCard(post, scope) {
  const isMine = store.get('user')?.id === post.user_id;
  const excerpt = renderTextBlock('摘抄', post.excerpt, 'quote');
  const content = renderTextBlock(contentLabel(post.post_type), post.content);
  const rating = post.post_type === 'finished' && post.rating != null
    ? `<div class="reading-post-rating"><span>评分</span><strong>${ratingEmoji(post.rating)} ${h(post.rating)}</strong></div>`
    : '';
  const moodColor = safeColor(post.mood_color, '');
  const moodStyle = moodColor ? `style="--reading-mood-border:${moodColor};"` : '';
  const cover = post.cover_url ? `
    <div class="reading-post-cover">
      <img src="${safeUrl(proxyImg(post.cover_url))}" alt="${esc(post.book_title)}">
    </div>
  ` : '';
  const titleLink = post.douban_url
    ? `<a href="${safeUrl(post.douban_url)}" target="_blank" rel="noopener">${h(formatBookTitle(post.book_title))}</a>`
    : h(formatBookTitle(post.book_title));
  const bookLine = post.author
    ? `${titleLink}<span class="reading-post-title-author"> - ${h(post.author)}</span>`
    : titleLink;

  postCache.set(Number(post.id), post);

  return `
    <article class="card reading-post-card" ${moodStyle}>
      <div class="card-body">
        <div class="reading-post-head">
          <div class="reading-post-user">
            <div class="reading-post-avatar">${renderAuthorAvatar(post)}</div>
            <div>
              <a href="#/user/${h(post.user_id)}" class="reading-post-username">${h(post.display_name || '书友')}</a>
              ${post.member_level > 0 ? `<span class="member-level-badge">Lv.${h(post.member_level)} ${h(post.member_title)}</span>` : ''}
              <span>${h(formatDateTime(post.created_at))}</span>
            </div>
          </div>
          <div class="reading-post-tags">
            <span class="tag tag-genre">${h(POST_TYPE_LABELS[post.post_type] || post.post_type)}</span>
            ${scope === 'mine' ? `<span class="tag tag-completed">${h(VISIBILITY_LABELS[post.visibility] || post.visibility)}</span>` : ''}
          </div>
        </div>
        <div class="reading-post-main">
          ${cover}
          <div class="reading-post-body">
            <div class="reading-post-title-row">
              <h3>${bookLine}</h3>
              ${rating}
            </div>
            ${excerpt}
            ${content}
          </div>
        </div>
        <div class="reading-post-foot">
          <button type="button" class="btn-like ${post.has_liked ? 'liked' : ''}" data-action="toggle-post-like" data-id="${h(post.id)}" title="${post.has_liked ? '取消点赞' : '点赞'}">
            <i data-lucide="heart"></i><span>${h(post.like_count || 0)}</span>
          </button>
          <button type="button" class="btn-comment-toggle" data-action="toggle-post-comments" data-id="${h(post.id)}" title="查看评论">
            <i data-lucide="message-circle"></i><span>${h(post.comment_count || 0)}</span>
          </button>
          ${isMine ? `
            <div class="reading-post-actions">
              <button type="button" class="btn btn-ghost btn-sm" data-action="edit-reading-post" data-id="${h(post.id)}">编辑</button>
              <button type="button" class="btn btn-ghost btn-sm" data-action="toggle-post-visibility" data-id="${h(post.id)}" data-next="${post.visibility === 'public' ? 'private' : 'public'}">
                ${post.visibility === 'public' ? '设为私密' : '设为公开'}
              </button>
              <button type="button" class="btn btn-danger btn-sm" data-action="delete-reading-post" data-id="${h(post.id)}">删除</button>
            </div>
          ` : ''}
        </div>
        <div class="reading-post-comments" data-post-comments="${h(post.id)}" style="display:none;">
          <div class="comments-list" data-comments-list="${h(post.id)}"></div>
          <form class="comment-form" data-comment-form="${h(post.id)}" novalidate>
            <textarea name="content" placeholder="写下你的评论..." required rows="2"></textarea>
            <button type="submit" class="btn btn-sm btn-primary">发送</button>
          </form>
        </div>
      </div>
    </article>
  `;
}

function renderPosts(posts, scope) {
  if (!posts.length) {
    return `
      <div class="empty-state">
        <i data-lucide="messages-square"></i>
        <p>${scope === 'mine' ? '你还没有发布书友圈动态。' : '还没有公开书友圈动态。'}</p>
      </div>
    `;
  }

  return `<div class="reading-post-list">${posts.map(post => renderPostCard(post, scope)).join('')}</div>`;
}

function buildDailyActivity(posts) {
  const map = new Map();
  posts.forEach(post => {
    const dateKey = dayjs(post.created_at).format('YYYY-MM-DD');
    const current = map.get(dateKey) || { count: 0, latestAt: 0, moodColor: '' };
    const createdAt = new Date(post.created_at).getTime();
    current.count += 1;
    if (!current.latestAt || createdAt >= current.latestAt) {
      current.latestAt = createdAt;
      current.moodColor = safeColor(post.mood_color, '');
    }
    map.set(dateKey, current);
  });
  return map;
}

function renderReadingActivityCalendar(posts, scope) {
  const now = dayjs();
  const todayStr = now.format('YYYY-MM-DD');
  const firstDay = now.startOf('month');
  const daysInMonth = firstDay.daysInMonth();
  const startDayOfWeek = firstDay.day();
  const prevMonthDays = firstDay.subtract(1, 'day').daysInMonth();
  const activity = buildDailyActivity(posts);
  const monthPrefix = now.format('YYYY-MM');
  const monthTotal = Array.from(activity.entries())
    .filter(([dateKey]) => dateKey.startsWith(monthPrefix))
    .reduce((sum, [, item]) => sum + item.count, 0);
  const todayCount = activity.get(todayStr)?.count || 0;

  let cells = CALENDAR_DAY_NAMES.map(d => `<div class="day-name">${d}</div>`).join('');
  for (let i = startDayOfWeek - 1; i >= 0; i--) {
    cells += `<div class="day other-month"><span>${prevMonthDays - i}</span></div>`;
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const dateKey = firstDay.date(d).format('YYYY-MM-DD');
    const dayActivity = activity.get(dateKey);
    let cls = 'day';
    if (dayActivity) {
      cls += ' checked';
    } else if (dateKey === todayStr) {
      cls += ' today';
    } else if (dayjs(dateKey).isAfter(now, 'day')) {
      cls += ' future';
    }
    const moodColor = safeColor(dayActivity?.moodColor, '#c17d4b');
    const style = dayActivity ? `style="--mood-dot:${moodColor}"` : '';
    const title = dayActivity ? `title="${dateKey} · ${dayActivity.count} 条动态"` : '';
    cells += `<div class="${cls}" ${style} ${title}><span>${d}</span></div>`;
  }

  const totalCells = startDayOfWeek + daysInMonth;
  const remaining = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  for (let d = 1; d <= remaining; d++) {
    cells += `<div class="day other-month"><span>${d}</span></div>`;
  }

  return `
    <section class="card reading-circle-calendar-card">
      <div class="card-body">
        <div class="member-panel-head">
          <div>
            <h3>本月书友圈</h3>
            <span>${scope === 'mine' ? '我的编写情况' : '广场编写情况'}</span>
          </div>
        </div>
        <div class="reading-circle-calendar-stats">
          <div>
            <span>今日</span>
            <strong>${h(todayCount)} 条</strong>
          </div>
          <div>
            <span>${now.format('M月')}</span>
            <strong>${h(monthTotal)} 条</strong>
          </div>
        </div>
        <div class="calendar reading-circle-calendar">
          <div class="calendar-header">
            <h4>${now.format('YYYY年M月')}</h4>
          </div>
          <div class="calendar-grid">${cells}</div>
        </div>
      </div>
    </section>
  `;
}

function renderPostComposer() {
  const user = store.get('user');
  return `
    <button class="btn btn-primary" data-action="open-reading-post-composer" ${user ? '' : 'disabled'}>
      <i data-lucide="square-pen"></i> 发布动态
    </button>
  `;
}

async function renderReadingCircle(scope = 'public') {
  const { posts, error } = await loadReadingPosts(scope);
  const user = store.get('user');

  return `
    <div class="container section reading-circle-page">
      <div class="member-heading">
        <div>
          <p class="member-eyebrow">书友圈</p>
          <h1>${scope === 'mine' ? '我的书友圈' : '书友圈广场'}</h1>
          <p>${scope === 'mine' ? '管理你的公开与私密阅读动态。' : '看见大家正在读、想读和读完的书。'}</p>
        </div>
        <div class="member-heading-actions">
          ${renderPostComposer()}
        </div>
      </div>

      <div class="tabs reading-circle-tabs">
        <a href="#/reading-circle" class="tab ${scope === 'public' ? 'active' : ''}">广场</a>
        <a href="#/reading-circle/mine" class="tab ${scope === 'mine' ? 'active' : ''}">我的动态</a>
      </div>

      ${!user ? '<div class="card reading-login-tip"><div class="card-body"><p>登录后可以发布阅读动态，并通过公开动态获得贡献值。</p><a href="#/login" class="btn btn-outline btn-sm">登录</a></div></div>' : ''}
      ${error ? '<div class="card reading-login-tip"><div class="card-body"><p>书友圈数据库尚未部署，请先执行 v13 SQL。</p></div></div>' : ''}
      ${scope === 'mine' ? `
        <div class="reading-circle-layout">
          <aside class="reading-circle-side">
            ${renderReadingActivityCalendar(posts, scope)}
          </aside>
          <section class="reading-circle-feed">
            ${renderPosts(posts, scope)}
          </section>
        </div>
      ` : renderPosts(posts, scope)}
    </div>
  `;
}

function showReadingPostComposer() {
  if (!store.get('user')) {
    toast('请先登录', 'error');
    router.navigate('/login?redirect=/reading-circle');
    return;
  }

  showModal('发布书友圈动态', `
    <form id="reading-post-form" novalidate>
      <div class="grid-2">
        <div class="form-group">
          <label>动态类型</label>
          <select name="post_type" required data-action="toggle-reading-rating">${postTypeOptions()}</select>
        </div>
        <div class="form-group">
          <label>可见范围</label>
          <select name="visibility" required>${visibilityOptions()}</select>
        </div>
      </div>
      <div class="form-group">
        <label>豆瓣链接</label>
        <div class="reading-douban-fetch-row">
          <input type="url" name="douban_url" required placeholder="https://book.douban.com/subject/...">
          <button type="button" class="btn btn-outline btn-sm" data-action="fetch-reading-douban">抓取</button>
        </div>
      </div>
      <div class="form-group">
        <label>书名</label>
        <input type="text" name="book_title" required readonly placeholder="从豆瓣链接自动抓取">
        <input type="hidden" name="author">
        <input type="hidden" name="cover_url">
      </div>
      <div class="reading-douban-preview" data-role="douban-preview">
        <i data-lucide="book-open"></i>
        <p>输入豆瓣链接后抓取书名、作者和封面。</p>
      </div>
      <div class="form-group reading-rating-group" style="display:none;">
        <label>读书评分</label>
        <input type="number" name="rating" min="-10" max="10" step="0.01" placeholder="-10 ~ 10，可精确到2位小数">
        <span class="form-hint">-10 ~ 10分制，可精确到2位小数。💩负分 &nbsp;🤢0~6 &nbsp;🙂6~8 &nbsp;👏🏻8~10</span>
      </div>
      <div class="form-group">
        <label>摘抄</label>
        <textarea name="excerpt" placeholder="可以单独记录触动你的原文句子。"></textarea>
      </div>
      <div class="form-group">
        <label>感想或书评</label>
        <textarea name="content" placeholder="写下你的阅读感想或书评。公开动态每日最多 3 条计入贡献值；正文达到 50 字会获得额外贡献值。"></textarea>
      </div>
      <div class="form-group">
        <label>阅读心情</label>
        <div class="mood-swatches reading-mood-swatches">
          ${MOODS.map(m => {
            const selectedClass = !m.value ? ' selected' : '';
            const style = m.value ? `background:${m.value};` : '';
            return `<button type="button" class="mood-swatch ${m.cls || ''}${selectedClass}"
              data-action="select-reading-mood"
              data-color="${m.value}" style="${style}"
              title="${m.label}" aria-label="${m.label}"></button>`;
          }).join('')}
        </div>
        <input type="hidden" name="mood_color" value="" id="reading-mood-color-input">
      </div>
      <div class="reading-post-form-actions">
        <button type="submit" class="btn btn-primary">发布</button>
      </div>
    </form>
  `);
}

function showReadingPostEditor(post) {
  if (!store.get('user')) {
    toast('请先登录', 'error');
    return;
  }

  const isFinished = post.post_type === 'finished';
  const isFinishedStyle = isFinished ? '' : 'style="display:none;"';

  const previewHtml = post.cover_url
    ? `<img src="${safeUrl(proxyImg(post.cover_url))}" alt="${esc(post.book_title)}">`
    : '<i data-lucide="book-open"></i>';

  const previewText = post.author
    ? `<strong>${h(formatBookTitle(post.book_title))}</strong><span>${h(post.author)}</span>`
    : `<strong>${h(formatBookTitle(post.book_title))}</strong>`;

  showModal('编辑书友圈动态', `
    <form id="reading-post-edit-form" novalidate>
      <input type="hidden" name="post_id" value="${h(post.id)}">
      <div class="grid-2">
        <div class="form-group">
          <label>动态类型</label>
          <select name="post_type" required data-action="toggle-reading-rating">${postTypeOptions(post.post_type)}</select>
        </div>
        <div class="form-group">
          <label>可见范围</label>
          <select name="visibility" required>${visibilityOptions(post.visibility)}</select>
        </div>
      </div>
      <div class="reading-douban-preview" data-role="douban-preview">
        ${previewHtml}
        <div>${previewText}</div>
      </div>
      <div class="form-group">
        <label>书名</label>
        <input type="text" value="${esc(post.book_title)}" readonly>
      </div>
      <div class="form-group reading-rating-group" ${isFinishedStyle}>
        <label>读书评分</label>
        <input type="number" name="rating" min="-10" max="10" step="0.01"
          value="${post.rating != null ? h(post.rating) : ''}"
          placeholder="-10 ~ 10，可精确到2位小数">
        <span class="form-hint">-10 ~ 10分制，可精确到2位小数。💩负分 &nbsp;🤢0~6 &nbsp;🙂6~8 &nbsp;👏🏻8~10</span>
      </div>
      <div class="form-group">
        <label>摘抄</label>
        <textarea name="excerpt" placeholder="可以单独记录触动你的原文句子。">${h(post.excerpt || '')}</textarea>
      </div>
      <div class="form-group">
        <label>感想或书评</label>
        <textarea name="content" placeholder="写下你的阅读感想或书评。">${h(post.content || '')}</textarea>
      </div>
      <div class="form-group">
        <label>阅读心情</label>
        <div class="mood-swatches reading-mood-swatches">
          ${MOODS.map(m => {
            const selected = m.value === (post.mood_color || '');
            const selectedClass = selected ? ' selected' : '';
            const style = m.value ? `background:${m.value};` : '';
            return `<button type="button" class="mood-swatch ${m.cls || ''}${selectedClass}"
              data-action="select-reading-mood"
              data-color="${m.value}" style="${style}"
              title="${m.label}" aria-label="${m.label}"></button>`;
          }).join('')}
        </div>
        <input type="hidden" name="mood_color" value="${esc(post.mood_color || '')}" id="reading-mood-color-input">
      </div>
      <div class="reading-post-form-actions">
        <button type="submit" class="btn btn-primary">保存修改</button>
      </div>
    </form>
  `);
}

async function fetchDoubanBookMeta(form) {
  const urlInput = form.querySelector('input[name="douban_url"]');
  const titleInput = form.querySelector('input[name="book_title"]');
  const authorInput = form.querySelector('input[name="author"]');
  const coverInput = form.querySelector('input[name="cover_url"]');
  const preview = form.querySelector('[data-role="douban-preview"]');
  const url = urlInput?.value?.trim();

  if (!isDoubanBookUrl(url)) {
    toast('请填写有效的豆瓣图书链接', 'error');
    return false;
  }

  if (preview) {
    preview.innerHTML = '<i data-lucide="loader"></i><p>正在抓取豆瓣图书信息...</p>';
    lucide.createIcons();
  }

  try {
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/fetch-douban-book`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({ url })
    });
    const result = await resp.json().catch(() => ({}));
    if (!resp.ok || !result?.success || !result?.data?.title) {
      throw new Error(result?.error || result?.detail || '未抓取到书籍信息');
    }

    const book = result.data;
    titleInput.value = book.title || '';
    authorInput.value = book.author || '';
    coverInput.value = book.cover_url || '';

    if (preview) {
      preview.innerHTML = `
        ${book.cover_url ? `<img src="${safeUrl(proxyImg(book.cover_url))}" alt="${esc(book.title)}">` : '<i data-lucide="book-open"></i>'}
        <div>
          <strong>${h(formatBookTitle(book.title))}</strong>
          ${book.author ? `<span>${h(book.author)}</span>` : '<span>作者信息未抓取到</span>'}
        </div>
      `;
      lucide.createIcons();
    }
    return true;
  } catch (err) {
    if (preview) {
      preview.innerHTML = '<i data-lucide="alert-triangle"></i><p>抓取失败，请检查 Edge Function 或豆瓣链接。</p>';
      lucide.createIcons();
    }
    toast('豆瓣信息抓取失败：' + (err.message || err), 'error');
    return false;
  }
}

async function submitReadingPost(form) {
  const fd = new FormData(form);
  const doubanUrl = fd.get('douban_url')?.trim();
  if (!isDoubanBookUrl(doubanUrl)) {
    toast('请填写有效的豆瓣图书链接', 'error');
    return;
  }

  if (!fd.get('book_title')) {
    const fetched = await fetchDoubanBookMeta(form);
    if (!fetched) return;
  }

  const refreshedFd = new FormData(form);
  const payload = {
    p_post_type: refreshedFd.get('post_type'),
    p_book_title: refreshedFd.get('book_title'),
    p_author: refreshedFd.get('author') || null,
    p_douban_url: refreshedFd.get('douban_url') || null,
    p_cover_url: refreshedFd.get('cover_url') || null,
    p_content: refreshedFd.get('content') || null,
    p_visibility: refreshedFd.get('visibility'),
    p_linked_book_id: null,
    p_excerpt: refreshedFd.get('excerpt') || null,
    p_mood_color: refreshedFd.get('mood_color') || null,
    p_rating: refreshedFd.get('rating') ? Number(refreshedFd.get('rating')) : null
  };

  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;

  const { error } = await sb.rpc('create_reading_post', payload);
  if (error) {
    toast('发布失败：' + error.message, 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  document.querySelector('#modal-container .modal-overlay')?.remove();
  await loadMemberSummary(store.get('user')?.id);
  toast('动态已发布');
  router.render();
}

async function updatePostVisibility(button) {
  const { id, next } = button.dataset;
  const { error } = await sb.rpc('update_reading_post_visibility', {
    p_post_id: Number(id),
    p_visibility: next
  });
  if (error) {
    toast('修改失败：' + error.message, 'error');
    return;
  }
  await loadMemberSummary(store.get('user')?.id);
  toast(next === 'public' ? '已设为公开' : '已设为私密');
  router.render();
}

async function deletePost(button) {
  if (!confirm('确定删除这条动态吗？删除后会回收对应贡献值。')) return;
  const { error } = await sb.rpc('delete_reading_post', {
    p_post_id: Number(button.dataset.id)
  });
  if (error) {
    toast('删除失败：' + error.message, 'error');
    return;
  }
  await loadMemberSummary(store.get('user')?.id);
  toast('动态已删除');
  router.render();
}

async function editReadingPost(form) {
  const fd = new FormData(form);
  const postId = Number(fd.get('post_id'));
  if (!postId) {
    toast('缺少动态ID', 'error');
    return;
  }

  const payload = {
    p_post_id: postId,
    p_post_type: fd.get('post_type'),
    p_visibility: fd.get('visibility'),
    p_excerpt: fd.get('excerpt') || '',
    p_content: fd.get('content') || '',
    p_mood_color: fd.get('mood_color') || '',
    p_rating: fd.get('rating') ? Number(fd.get('rating')) : null
  };

  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;

  const { error } = await sb.rpc('update_reading_post', payload);
  if (error) {
    toast('保存失败：' + error.message, 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  document.querySelector('#modal-container .modal-overlay')?.remove();
  postCache.delete(postId);
  await loadMemberSummary(store.get('user')?.id);
  toast('动态已更新');
  router.render();
}

// ---- 点赞 ----

async function toggleLike(button) {
  const user = store.get('user');
  if (!user) {
    toast('请先登录', 'error');
    router.navigate('/login?redirect=/reading-circle');
    return;
  }

  const postId = Number(button.dataset.id);
  button.disabled = true;

  const { data, error } = await sb.rpc('toggle_post_like', { p_post_id: postId });
  if (error) {
    toast(error.message, 'error');
    button.disabled = false;
    return;
  }

  const wasLiked = button.classList.contains('liked');
  const countSpan = button.querySelector('span');
  const currentCount = parseInt(countSpan?.textContent) || 0;

  if (data === 'liked') {
    button.classList.add('liked');
    if (countSpan) countSpan.textContent = currentCount + 1;
    button.title = '取消点赞';
  } else {
    button.classList.remove('liked');
    if (countSpan) countSpan.textContent = Math.max(currentCount - 1, 0);
    button.title = '点赞';
  }

  button.disabled = false;
}

// ---- 评论 ----

async function toggleComments(button) {
  const postId = button.dataset.id;
  const commentsSection = document.querySelector(`[data-post-comments="${postId}"]`);
  if (!commentsSection) return;

  const isHidden = commentsSection.style.display === 'none';
  if (isHidden) {
    commentsSection.style.display = '';
    await loadComments(postId);
    // 聚焦输入框
    const form = commentsSection.querySelector('form');
    form?.querySelector('textarea')?.focus();
  } else {
    commentsSection.style.display = 'none';
  }
}

async function loadComments(postId) {
  const listEl = document.querySelector(`[data-comments-list="${postId}"]`);
  if (!listEl) return;

  listEl.innerHTML = '<div class="comments-loading"><i data-lucide="loader"></i></div>';
  if (typeof lucide !== 'undefined') lucide.createIcons();

  const { data, error } = await sb.rpc('list_comments', { p_post_id: Number(postId) });
  if (error) {
    listEl.innerHTML = `<div class="comments-error">加载失败：${error.message}</div>`;
    return;
  }

  renderComments(listEl, data || [], postId);
}

function renderComments(listEl, comments, postId) {
  if (!comments.length) {
    listEl.innerHTML = '<div class="comments-empty">暂无评论，来写第一条吧</div>';
    return;
  }

  const currentUserId = store.get('user')?.id;

  listEl.innerHTML = comments.map(c => `
    <div class="comment-item">
      <div class="comment-avatar">${c.avatar_url ? `<img src="${safeUrl(c.avatar_url)}" alt="">` : h((c.display_name || '书')[0].toUpperCase())}</div>
      <div class="comment-body">
        <div class="comment-head">
          <strong>${h(c.display_name || '书友')}</strong>
          <span>${h(formatDateTime(c.created_at))}</span>
        </div>
        <p class="comment-text">${h(c.content)}</p>
        ${c.user_id === currentUserId ? `
          <button type="button" class="btn-comment-delete" data-action="delete-comment" data-id="${h(c.id)}" data-post="${h(postId)}" title="删除评论">
            <i data-lucide="trash-2"></i>
          </button>
        ` : ''}
      </div>
    </div>
  `).join('');

  if (typeof lucide !== 'undefined') lucide.createIcons();
}

async function submitComment(form) {
  const user = store.get('user');
  if (!user) {
    toast('请先登录', 'error');
    router.navigate('/login?redirect=/reading-circle');
    return;
  }

  const postId = Number(form.dataset.commentForm);
  const textarea = form.querySelector('textarea');
  const content = textarea?.value?.trim();
  if (!content) return;

  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;

  const { data: commentId, error } = await sb.rpc('create_comment', {
    p_post_id: postId,
    p_content: content
  });

  if (error) {
    toast(error.message, 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  textarea.value = '';
  if (submitBtn) submitBtn.disabled = false;

  // 更新评论计数
  const toggleBtn = document.querySelector(`[data-action="toggle-post-comments"][data-id="${postId}"]`);
  const countSpan = toggleBtn?.querySelector('span');
  if (countSpan) {
    countSpan.textContent = (parseInt(countSpan.textContent) || 0) + 1;
  }

  await loadComments(postId);
}

async function deleteComment(button) {
  if (!confirm('确定删除这条评论吗？')) return;

  const commentId = Number(button.dataset.id);
  const postId = button.dataset.post;

  const { error } = await sb.rpc('delete_comment', { p_comment_id: commentId });
  if (error) {
    toast('删除失败：' + error.message, 'error');
    return;
  }

  // 更新评论计数
  const toggleBtn = document.querySelector(`[data-action="toggle-post-comments"][data-id="${postId}"]`);
  const countSpan = toggleBtn?.querySelector('span');
  if (countSpan) {
    countSpan.textContent = Math.max((parseInt(countSpan.textContent) || 1) - 1, 0);
  }

  await loadComments(postId);
}

async function renderUserProfile(userId) {
  const [profileRes, postsRes, badgesRes] = await Promise.all([
    sb.rpc('get_public_member_profile', { p_user_id: userId }),
    sb.rpc('list_user_public_posts', { p_user_id: userId }),
    sb.from('user_badges')
      .select('*, badge_catalog(*)')
      .eq('user_id', userId)
      .is('revoked_at', null)
      .order('awarded_at', { ascending: false })
      .limit(6)
  ]);

  const profile = profileRes.data?.[0];
  const posts = postsRes.data || [];
  const badges = badgesRes.data || [];

  if (!profile) {
    return '<div class="container section"><div class="empty-state"><i data-lucide="user-x"></i><p>用户不存在</p></div></div>';
  }

  const avatarHtml = profile.avatar_url
    ? `<img src="${safeUrl(profile.avatar_url)}" alt="">`
    : h((profile.display_name || '书')[0].toUpperCase());

  const badgeItems = badges.length
    ? badges.map(b => {
        const badge = b.badge_catalog || {};
        const bucket = badge.image_bucket;
        const path = badge.image_path;
        let imageUrl = '';
        if (bucket && path) {
          const { data: publicUrl } = sb.storage.from(bucket).getPublicUrl(path);
          imageUrl = publicUrl?.publicUrl || '';
        }
        const title = badge.level && badge.title ? `Lv.${badge.level} ${badge.title}` : (badge.title || '徽章');
        const awardedAt = b.awarded_at ? formatDateTime(b.awarded_at) : '';
        const imgHtml = imageUrl
          ? `<img src="${safeUrl(imageUrl)}" alt="${esc(title)}">`
          : '<i data-lucide="shield"></i>';
        return `
          <button type="button" class="user-badge-item"
            data-action="member-badge-preview"
            data-badge-title="${esc(title)}"
            data-badge-date="${esc(awardedAt)}"
            data-badge-image="${esc(imageUrl)}"
            title="${esc(title)}">
            ${imgHtml}
          </button>`;
      }).join('')
    : '<div class="user-no-badges">暂无徽章</div>';

  const statsHtml = `
    <div class="user-stats">
      <div class="user-stat"><span>总贡献</span><strong>${h(profile.contribution_total)}</strong></div>
      <div class="user-stat"><span>本月</span><strong>${h(profile.contribution_month)}</strong></div>
      <div class="user-stat"><span>本周</span><strong>${h(profile.contribution_week)}</strong></div>
    </div>`;

  return `
    <div class="container section user-profile-page">
      <a href="#/reading-circle" class="user-profile-back"><i data-lucide="arrow-left"></i> 返回书友圈</a>

      <div class="card user-profile-card">
        <div class="card-body">
          <div class="user-profile-head">
            <div class="user-profile-avatar">${avatarHtml}</div>
            <div class="user-profile-info">
              <h2>${h(profile.display_name || '书友')}</h2>
              ${profile.level > 0 ? `<div class="user-profile-level"><span class="member-level-badge">Lv.${h(profile.level)} ${h(profile.title)}</span><span class="user-tier">${h(profile.tier)}</span></div>` : `<div class="user-profile-level"><span class="user-tier">${h(profile.tier)}</span></div>`}
              ${statsHtml}
            </div>
          </div>
        </div>
      </div>

      <div class="card user-badges-card">
        <div class="card-body">
          <h3>徽章</h3>
          <div class="user-badges-grid">${badgeItems}</div>
        </div>
      </div>

      <section>
        <h3 style="margin-bottom:var(--space-3);">${h(profile.display_name || '书友')} 的书友圈</h3>
        ${posts.length ? renderPosts(posts, 'public') : '<div class="empty-state"><i data-lucide="messages-square"></i><p>还没有公开发布的书友圈动态。</p></div>'}
      </section>
    </div>
  `;
}

export function registerReadingPostRoutes() {
  route('/reading-circle', () => renderReadingCircle('public'));
  route('/reading-circle/mine', () => renderReadingCircle('mine'));
  route('/user/:userId', (params) => renderUserProfile(params.userId));
}

export function bindReadingPostEvents() {
  document.addEventListener('click', async e => {
    const composer = e.target.closest('[data-action="open-reading-post-composer"]');
    if (composer) {
      showReadingPostComposer();
      return;
    }

    const editBtn = e.target.closest('[data-action="edit-reading-post"]');
    if (editBtn) {
      const post = postCache.get(Number(editBtn.dataset.id));
      if (post) {
        showReadingPostEditor(post);
      } else {
        toast('动态数据加载失败，请刷新页面', 'error');
      }
      return;
    }

    const visibilityBtn = e.target.closest('[data-action="toggle-post-visibility"]');
    if (visibilityBtn) {
      await updatePostVisibility(visibilityBtn);
      return;
    }

    const deleteBtn = e.target.closest('[data-action="delete-reading-post"]');
    if (deleteBtn) {
      await deletePost(deleteBtn);
      return;
    }

    const fetchDoubanBtn = e.target.closest('[data-action="fetch-reading-douban"]');
    if (fetchDoubanBtn) {
      await fetchDoubanBookMeta(fetchDoubanBtn.closest('#reading-post-form'));
      return;
    }

    const moodBtn = e.target.closest('[data-action="select-reading-mood"]');
    if (moodBtn) {
      const form = moodBtn.closest('form');
      if (!form) return;
      form.querySelectorAll('.reading-mood-swatches .mood-swatch').forEach(btn => btn.classList.remove('selected'));
      moodBtn.classList.add('selected');
      const colorInput = form.querySelector('input[name="mood_color"]');
      if (colorInput) colorInput.value = moodBtn.dataset.color || '';
    }

    const likeBtn = e.target.closest('[data-action="toggle-post-like"]');
    if (likeBtn) {
      await toggleLike(likeBtn);
      return;
    }

    const commentToggleBtn = e.target.closest('[data-action="toggle-post-comments"]');
    if (commentToggleBtn) {
      await toggleComments(commentToggleBtn);
      return;
    }

    const deleteCommentBtn = e.target.closest('[data-action="delete-comment"]');
    if (deleteCommentBtn) {
      await deleteComment(deleteCommentBtn);
      return;
    }
  });

  document.addEventListener('change', async e => {
    const doubanInput = e.target.closest('form input[name="douban_url"]');
    if (doubanInput && doubanInput.value) {
      await fetchDoubanBookMeta(doubanInput.closest('form'));
    }

    const ratingToggle = e.target.closest('[data-action="toggle-reading-rating"]');
    if (ratingToggle) {
      const form = ratingToggle.closest('form');
      if (!form) return;
      const ratingGroup = form.querySelector('.reading-rating-group');
      const ratingInput = ratingGroup?.querySelector('input[name="rating"]');
      if (ratingToggle.value === 'finished') {
        if (ratingGroup) ratingGroup.style.display = '';
      } else {
        if (ratingGroup) ratingGroup.style.display = 'none';
        if (ratingInput) ratingInput.value = '';
      }
    }
  });

  document.addEventListener('submit', async e => {
    if (e.target.id === 'reading-post-form') {
      e.preventDefault();
      await submitReadingPost(e.target);
    }
    if (e.target.id === 'reading-post-edit-form') {
      e.preventDefault();
      await editReadingPost(e.target);
    }
    if (e.target.classList.contains('comment-form')) {
      e.preventDefault();
      await submitComment(e.target);
    }
  });
}
