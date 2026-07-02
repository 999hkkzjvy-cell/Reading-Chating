import { loadMemberSummary } from './members.js';
import { fetchDoubanBook } from './readingPostApi.js';
import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { signOut } from './auth.js';
import { store } from './store.js';
import { showModal, toast } from './ui.js';
import { esc, formatDate, formatDateTime, h, isDoubanBookUrl, normalizeDoubanBookUrl, proxyImg, safeUrl } from './utils.js';
import { getBadgeRiddle } from './badgeRiddles.js';

const memberLibraryItemCache = new Map();

function storagePublicUrl(bucket, path) {
  if (!bucket || !path) return '';
  const { data } = sb.storage.from(bucket).getPublicUrl(path);
  return data?.publicUrl || '';
}

function getBadgeImageUrl(badgeCatalog) {
  if (!badgeCatalog) return '';
  return storagePublicUrl(badgeCatalog.image_bucket, badgeCatalog.image_path);
}

function getBadgeBackImageUrl(badgeCatalog) {
  if (!badgeCatalog) return '';
  return storagePublicUrl(badgeCatalog.back_image_bucket || badgeCatalog.image_bucket, badgeCatalog.back_image_path);
}

function badgeDisplayTitle(row) {
  const badge = row.badge_catalog || {};
  if (badge.badge_type === 'founder' || row.badge_type === 'founder') {
    return badge.title || '开创者';
  }
  if (badge.level && badge.title) {
    return `Lv.${badge.level} ${badge.title}`;
  }
  return badge.title || row.badge_key;
}

function sortBadgesForDisplay(badges) {
  const list = [...(badges || [])];
  const founder = list.filter(row => row.badge_key === 'founder' || row.badge_type === 'founder');
  const rest = list
    .filter(row => row.badge_key !== 'founder' && row.badge_type !== 'founder')
    .sort((a, b) => new Date(b.awarded_at || 0) - new Date(a.awarded_at || 0));
  return [...founder, ...rest];
}

function sortBadgesForCatalogOrder(badges) {
  return [...(badges || [])].sort((a, b) => {
    const aBadge = a.badge_catalog || {};
    const bBadge = b.badge_catalog || {};
    const aFounder = a.badge_key === 'founder' || a.badge_type === 'founder';
    const bFounder = b.badge_key === 'founder' || b.badge_type === 'founder';
    if (aFounder !== bFounder) return aFounder ? -1 : 1;

    const aLevel = Number.isFinite(Number(aBadge.level)) ? Number(aBadge.level) : 999;
    const bLevel = Number.isFinite(Number(bBadge.level)) ? Number(bBadge.level) : 999;
    if (aLevel !== bLevel) return aLevel - bLevel;

    return new Date(b.awarded_at || 0) - new Date(a.awarded_at || 0);
  });
}

function memberLibraryKey(listType, sortOrder) {
  return `${listType}:${sortOrder}`;
}

function getLibraryConfig(listType) {
  return listType === 'life'
    ? { title: '人生之书', max: 3, reasonLabel: '推荐理由', emptyText: '设置一本人生之书' }
    : { title: '想读书目', max: 5, reasonLabel: '想读理由', emptyText: '添加一本想读书' };
}

function activeLibraryTab() {
  const tab = router.currentQuery().tab || 'finished';
  return ['finished', 'want', 'life'].includes(tab) ? tab : 'finished';
}

function renderLibraryTabs(active) {
  const tabs = [
    ['finished', '已读书目'],
    ['want', '想读书目'],
    ['life', '人生之书']
  ];
  return `
    <div class="tabs member-library-tabs">
      ${tabs.map(([key, label]) => `<a href="#/member/library?tab=${key}" class="tab ${active === key ? 'active' : ''}">${label}</a>`).join('')}
    </div>
  `;
}

function renderLibraryCover(url, title) {
  return `
    <div class="member-library-cover">
      ${url ? `<img src="${safeUrl(proxyImg(url))}" alt="${esc(title || '书籍封面')}">` : '<i data-lucide="book-open"></i>'}
    </div>
  `;
}

function shortLibraryText(text, max = 72) {
  const value = String(text || '').replace(/\s+/g, ' ').trim();
  if (!value) return '';
  return value.length > max ? `${value.slice(0, max)}...` : value;
}

function renderFinishedLibrary(finishedBooks) {
  if (!finishedBooks?.length) {
    return '<div class="empty-state"><i data-lucide="book-check"></i><p>还没有通过书友圈标记已读的书目。</p></div>';
  }

  return `
    <div class="member-library-grid">
      ${finishedBooks.map(book => `
        <a href="#/reading-circle/mine?post=${h(book.post_id)}" class="member-library-card">
          ${renderLibraryCover(book.cover_url, book.book_title)}
          <div class="member-library-card-body">
            <strong>${h(book.book_title || '未命名书目')}</strong>
            ${book.author ? `<span>${h(book.author)}</span>` : ''}
            ${book.content ? `<p>${h(shortLibraryText(book.content))}</p>` : ''}
            <small>${h(formatDate(book.finished_at))}${Number(book.post_count || 0) > 1 ? ` · ${h(book.post_count)} 条已读动态` : ''}</small>
          </div>
        </a>
      `).join('')}
    </div>
  `;
}

function renderEditableLibrary(listType, items) {
  const config = getLibraryConfig(listType);
  const byOrder = new Map((items || []).filter(item => item.list_type === listType).map(item => [Number(item.sort_order), item]));
  const slots = Array.from({ length: config.max }, (_, index) => index + 1);

  slots.forEach(order => {
    const item = byOrder.get(order);
    if (item) memberLibraryItemCache.set(memberLibraryKey(listType, order), item);
  });

  return `
    <div class="member-library-slots member-library-slots-${h(listType)}">
      ${slots.map(order => {
        const item = byOrder.get(order);
        if (!item) {
          return `
            <button type="button" class="member-library-empty-slot" data-action="member-library-edit" data-list-type="${listType}" data-sort-order="${order}">
              <span>${h(order)}</span>
              <i data-lucide="plus"></i>
              ${h(config.emptyText)}
            </button>
          `;
        }

        return `
          <div class="member-library-slot-card">
            <div class="member-library-slot-rank">${h(order)}</div>
            ${renderLibraryCover(item.cover_url, item.book_title)}
            <div class="member-library-card-body">
              <strong>${h(item.book_title || '未命名书目')}</strong>
              ${item.author ? `<span>${h(item.author)}</span>` : ''}
              ${item.reason ? `<p>${h(shortLibraryText(item.reason, 96))}</p>` : `<p class="muted">${h(config.reasonLabel)}待补充</p>`}
              <small>更新：${h(formatDate(item.updated_at))}</small>
            </div>
            <div class="member-library-slot-actions">
              <button type="button" class="btn btn-outline btn-sm" data-action="member-library-edit" data-list-type="${listType}" data-sort-order="${order}"><i data-lucide="edit-3"></i> 编辑</button>
              <button type="button" class="btn btn-ghost btn-sm" data-action="member-library-delete" data-list-type="${listType}" data-sort-order="${order}"><i data-lucide="trash-2"></i> 删除</button>
            </div>
          </div>
        `;
      }).join('')}
    </div>
  `;
}

async function loadMemberLibrary() {
  const [finishedRes, itemRes] = await Promise.all([
    sb.rpc('list_my_finished_books'),
    sb.rpc('list_my_member_library_items')
  ]);

  return {
    finishedBooks: finishedRes.data || [],
    items: itemRes.data || [],
    error: finishedRes.error || itemRes.error
  };
}

function renderMemberLibraryError(error) {
  return `
    <div class="container section">
      <div class="empty-state">
        <i data-lucide="database"></i>
        <p>我的书库暂不可用：${h(error?.message || '请先部署 v38 我的书库 SQL。')}</p>
      </div>
    </div>
  `;
}

function renderMemberLibraryPreview(book) {
  if (!book?.title) {
    return '<div class="member-library-form-preview empty"><i data-lucide="book-open"></i><p>抓取豆瓣链接后，将在这里显示书籍信息。</p></div>';
  }

  return `
    <div class="member-library-form-preview">
      ${renderLibraryCover(book.cover_url, book.title)}
      <div>
        <strong>${h(book.title)}</strong>
        ${book.author ? `<span>${h(book.author)}</span>` : '<span>作者信息未抓取到</span>'}
      </div>
    </div>
  `;
}

function showMemberLibraryItemModal(listType, sortOrder) {
  const config = getLibraryConfig(listType);
  const item = memberLibraryItemCache.get(memberLibraryKey(listType, Number(sortOrder))) || null;
  const book = item ? {
    title: item.book_title,
    author: item.author,
    cover_url: item.cover_url
  } : null;

  showModal(`${config.title} · 第 ${sortOrder} 位`, `
    <form id="member-library-item-form" data-loaded-url="${esc(item?.douban_url || '')}">
      <input type="hidden" name="list_type" value="${esc(listType)}">
      <input type="hidden" name="sort_order" value="${esc(sortOrder)}">
      <input type="hidden" name="book_title" value="${esc(item?.book_title || '')}">
      <input type="hidden" name="author" value="${esc(item?.author || '')}">
      <input type="hidden" name="cover_url" value="${esc(item?.cover_url || '')}">

      <div class="form-group">
        <label>豆瓣链接 *</label>
        <div class="member-library-url-row">
          <input type="url" name="douban_url" required placeholder="https://book.douban.com/subject/..." value="${esc(item?.douban_url || '')}">
          <button type="button" class="btn btn-outline btn-sm" data-action="member-library-fetch-book"><i data-lucide="search"></i> 抓取</button>
        </div>
      </div>

      <div id="member-library-book-preview">
        ${renderMemberLibraryPreview(book)}
      </div>

      <div class="form-group">
        <label>${h(config.reasonLabel)}</label>
        <textarea name="reason" maxlength="1000" style="min-height:110px;" placeholder="${h(config.reasonLabel)}，最多 1000 字。">${h(item?.reason || '')}</textarea>
      </div>

      <button type="submit" class="btn btn-primary" style="width:100%;">保存</button>
    </form>
  `);
}

async function fetchMemberLibraryBookMeta(form) {
  const urlInput = form.querySelector('input[name="douban_url"]');
  const titleInput = form.querySelector('input[name="book_title"]');
  const authorInput = form.querySelector('input[name="author"]');
  const coverInput = form.querySelector('input[name="cover_url"]');
  const preview = form.querySelector('#member-library-book-preview');
  const normalizedUrl = normalizeDoubanBookUrl(urlInput?.value || '').trim();

  if (!isDoubanBookUrl(normalizedUrl)) {
    toast('请填写有效的豆瓣读书链接', 'error');
    return null;
  }

  if (preview) preview.innerHTML = '<div class="member-library-form-preview empty"><i data-lucide="loader"></i><p>正在抓取书籍信息...</p></div>';
  if (typeof lucide !== 'undefined') lucide.createIcons();

  const book = await fetchDoubanBook(normalizedUrl);
  urlInput.value = normalizedUrl;
  titleInput.value = book.title || '';
  authorInput.value = book.author || '';
  coverInput.value = book.cover_url || '';
  form.dataset.loadedUrl = normalizedUrl;
  if (preview) preview.innerHTML = renderMemberLibraryPreview(book);
  if (typeof lucide !== 'undefined') lucide.createIcons();
  return book;
}

async function submitMemberLibraryItem(form) {
  const fd = new FormData(form);
  const normalizedUrl = normalizeDoubanBookUrl(fd.get('douban_url') || '').trim();

  if (!isDoubanBookUrl(normalizedUrl)) {
    toast('请填写有效的豆瓣读书链接', 'error');
    return;
  }

  if (!fd.get('book_title') || form.dataset.loadedUrl !== normalizedUrl) {
    try {
      await fetchMemberLibraryBookMeta(form);
    } catch (err) {
      toast('抓取失败：' + (err.message || '未知错误'), 'error');
      return;
    }
  }

  const refreshed = new FormData(form);
  const { error } = await sb.rpc('upsert_my_member_library_item', {
    p_list_type: refreshed.get('list_type'),
    p_sort_order: Number(refreshed.get('sort_order')),
    p_book_title: refreshed.get('book_title'),
    p_author: refreshed.get('author') || null,
    p_douban_url: normalizeDoubanBookUrl(refreshed.get('douban_url')),
    p_cover_url: refreshed.get('cover_url') || null,
    p_reason: refreshed.get('reason') || ''
  });

  if (error) {
    toast('保存失败：' + error.message, 'error');
    return;
  }

  document.querySelector('.modal-overlay')?.remove();
  toast('我的书库已更新');
  router.render();
}

async function deleteMemberLibraryItem(button) {
  const listType = button.dataset.listType;
  const sortOrder = Number(button.dataset.sortOrder);
  if (!confirm('确定删除这个书目吗？删除后后台不保留该条数据。')) return;

  button.disabled = true;
  const { error } = await sb.rpc('delete_my_member_library_item', {
    p_list_type: listType,
    p_sort_order: sortOrder
  });
  if (error) {
    toast('删除失败：' + error.message, 'error');
    button.disabled = false;
    return;
  }
  toast('已删除');
  router.render();
}

function selectedDisplayBadgeKeys(member) {
  const badges = member?.badges || [];
  const byKey = new Map(badges.map(row => [row.badge_key, row]));
  const founder = badges.find(row => row.badge_key === 'founder' || row.badge_type === 'founder');
  const prefKeys = (member?.badgeDisplayPreferences || [])
    .map(row => row.badge_key)
    .filter(key => byKey.has(key));

  if (prefKeys.length > 0) {
    const keys = founder && !prefKeys.includes(founder.badge_key)
      ? [founder.badge_key, ...prefKeys]
      : prefKeys;
    const filledKeys = [...keys];
    sortBadgesForDisplay(badges).forEach(row => {
      if (filledKeys.length < 6 && !filledKeys.includes(row.badge_key)) {
        filledKeys.push(row.badge_key);
      }
    });
    return filledKeys.slice(0, 6);
  }

  return sortBadgesForDisplay(badges).slice(0, 6).map(row => row.badge_key);
}

function displayBadgesForMember(member) {
  const byKey = new Map((member?.badges || []).map(row => [row.badge_key, row]));
  return selectedDisplayBadgeKeys(member).map(key => byKey.get(key)).filter(Boolean);
}

function renderStat(label, value, icon, detail = '') {
  return `
    <div class="member-stat-card">
      <i data-lucide="${icon}"></i>
      <div>
        <span>${h(label)}</span>
        <strong>${h(value)}</strong>
        ${detail ? `<em>${h(detail)}</em>` : ''}
      </div>
    </div>
  `;
}

function isViewPassUsable(pass) {
  return pass?.status === 'available' && (!pass.expires_at || new Date(pass.expires_at) > new Date());
}

function isRedemptionTicketUsable(ticket) {
  return ticket?.status === 'available';
}

function ticketSummary(member) {
  const viewPasses = member?.viewPasses || [];
  const redemptionTickets = member?.redemptionTickets || [];
  const availableViewPasses = viewPasses.filter(isViewPassUsable).length;
  const availableRedemptionTickets = redemptionTickets.filter(isRedemptionTicketUsable).length;

  return {
    viewPasses,
    redemptionTickets,
    availableViewPasses,
    unavailableViewPasses: Math.max(viewPasses.length - availableViewPasses, 0),
    availableRedemptionTickets,
    unavailableRedemptionTickets: Math.max(redemptionTickets.length - availableRedemptionTickets, 0)
  };
}

function remainingText(date) {
  if (!date) return '长期有效';
  const ms = new Date(date).getTime() - Date.now();
  if (!Number.isFinite(ms) || ms <= 0) return '已到期';
  const days = Math.floor(ms / 86400000);
  const hours = Math.floor((ms % 86400000) / 3600000);
  const minutes = Math.floor((ms % 3600000) / 60000);
  if (days > 0) return `还剩 ${days} 天 ${hours} 小时`;
  if (hours > 0) return `还剩 ${hours} 小时 ${minutes} 分钟`;
  return `还剩 ${Math.max(minutes, 1)} 分钟`;
}

function statusLabel(type, item) {
  if (type === 'view' && item.status === 'available' && item.expires_at && new Date(item.expires_at) <= new Date()) {
    return { text: '已过期', tone: 'muted' };
  }
  const labels = {
    available: { text: '可用', tone: 'success' },
    used: { text: '已使用', tone: 'muted' },
    expired: { text: '已过期', tone: 'muted' },
    revoked: { text: '已回收', tone: 'danger' }
  };
  return labels[item.status] || { text: item.status || '未知', tone: 'muted' };
}

function reasonLabel(reason) {
  const labels = {
    signup: '注册奖励',
    weekly: '每周发放',
    active_bonus: '活跃奖励',
    admin: '管理员发放',
    level_up: '升级奖励'
  };
  return labels[reason] || reason || '未标注';
}

function renderTicketSummary(member) {
  const summary = ticketSummary(member);
  return `
    <a href="#/member/tickets" class="member-ticket-summary-card">
      <div>
        <i data-lucide="ticket"></i>
        <span><b>资源浏览券</b><small>${h(summary.unavailableViewPasses)} 不可用</small></span>
        <strong>${h(summary.availableViewPasses)} 可用</strong>
      </div>
      <div>
        <i data-lucide="key-round"></i>
        <span><b>共读兑换券</b><small>${h(summary.unavailableRedemptionTickets)} 不可用</small></span>
        <strong>${h(summary.availableRedemptionTickets)} 可用</strong>
      </div>
      <span class="member-ticket-summary-more">查看全部票券 <i data-lucide="chevron-right"></i></span>
    </a>
  `;
}

function renderTicketRows(type, tickets) {
  if (!tickets.length) {
    return `
      <div class="member-empty-inline compact">
        <i data-lucide="${type === 'view' ? 'ticket' : 'key-round'}"></i>
        <p>暂无${type === 'view' ? '资源浏览券' : '共读兑换券'}。</p>
      </div>
    `;
  }

  return `
    <div class="member-ticket-detail-list">
      ${tickets.map(ticket => {
        const status = statusLabel(type, ticket);
        const isView = type === 'view';
        const title = isView ? `资源浏览券 #${ticket.id}` : `共读兑换券 #${ticket.id}`;
        const validity = isView
          ? `${ticket.expires_at ? formatDateTime(ticket.expires_at) : '长期有效'} · ${remainingText(ticket.expires_at)}`
          : (ticket.status === 'available' ? '长期有效' : (ticket.used_at ? `使用于 ${formatDateTime(ticket.used_at)}` : '无有效期'));
        const extra = isView
          ? [
              ticket.used_resource_key ? `资源：${ticket.used_resource_key}` : '',
              ticket.temporary_access_expires_at ? `临时权限至：${formatDateTime(ticket.temporary_access_expires_at)}` : ''
            ].filter(Boolean).join(' · ')
          : [
              ticket.issued_level ? `来源等级：Lv.${ticket.issued_level}` : '',
              ticket.used_book_id ? `兑换书目 ID：${ticket.used_book_id}` : ''
            ].filter(Boolean).join(' · ');
        return `
          <div class="member-ticket-detail-card">
            <div class="member-ticket-detail-title">
              <h4>${h(title)}</h4>
              <span class="ticket-status ticket-status-${h(status.tone)}">${h(status.text)}</span>
            </div>
            <p>${h(reasonLabel(ticket.issued_reason))} · 发放于 ${h(formatDateTime(ticket.issued_at))}</p>
            <p>${h(validity)}</p>
            ${extra ? `<p>${h(extra)}</p>` : ''}
          </div>
        `;
      }).join('')}
    </div>
  `;
}

function renderAccessGrants(member) {
  const grants = member?.accessGrants || [];
  if (!grants.length) {
    return `
      <div class="member-empty-inline compact">
        <i data-lucide="lock-open"></i>
        <p>你还没有永久解锁的共读资源。</p>
      </div>
    `;
  }

  return `
    <div class="member-ticket-detail-list">
      ${grants.map(grant => `
        <div class="member-ticket-detail-card">
          <div class="member-ticket-detail-title">
            <h4>${h(grant.books?.title || `书目 #${grant.book_id}`)}</h4>
            <span class="ticket-status ticket-status-success">永久</span>
          </div>
          <p>${grant.books?.author ? `${h(grant.books.author)} · ` : ''}${h(grantTypeLabel(grant.grant_type))} · 解锁于 ${h(formatDateTime(grant.created_at))}</p>
        </div>
      `).join('')}
    </div>
  `;
}

function grantTypeLabel(type) {
  const map = {
    redeemed: '共读兑换券',
    commemorative: '共读纪念券',
    founder: '开创者权限',
    admin: '管理员授予'
  };
  return map[type] || '资源权限';
}

function renderProgress(stats, currentLevel, nextLevel) {
  if (!stats || !currentLevel) {
    return '<div class="member-progress-bar"><span style="width:0%;"></span></div>';
  }

  if (!nextLevel) {
    return `
      <div class="member-progress-copy">
        <span>已到达当前最高等级</span>
        <strong>Lv.${h(stats.level)}</strong>
      </div>
      <div class="member-progress-bar"><span style="width:100%;"></span></div>
    `;
  }

  const current = Number(stats.contribution_total || 0);
  const min = Number(currentLevel.min_contribution || 0);
  const nextMin = Number(nextLevel.min_contribution || 0);
  const span = Math.max(nextMin - min, 1);
  const gained = Math.max(current - min, 0);
  const percent = Math.max(0, Math.min(100, Math.round((gained / span) * 100)));
  const needed = Math.max(nextMin - current, 0);

  return `
    <div class="member-progress-copy">
      <span>距离 Lv.${h(nextLevel.level)} ${h(nextLevel.title)} 还需 ${h(needed)} 贡献值</span>
      <strong>${h(percent)}%</strong>
    </div>
    <div class="member-progress-bar"><span style="width:${percent}%;"></span></div>
  `;
}

function renderBadgeList(badges, opts = {}) {
  if (!badges?.length) {
    return `
      <div class="member-empty-inline">
        <i data-lucide="badge"></i>
        <p>还没有获得徽章。完成阅读动态和贡献任务后，这里会慢慢亮起来。</p>
      </div>
    `;
  }

  const sortedBadges = opts.preserveOrder ? [...badges] : sortBadgesForDisplay(badges);
  const visibleBadges = opts.limit ? sortedBadges.slice(0, opts.limit) : sortedBadges;
  const totalCount = opts.totalCount ?? sortedBadges.length;
  const showMore = opts.showMore && totalCount > 0;
  const moreText = totalCount > opts.limit ? '更多徽章' : '管理徽章';
  const answeredKeys = new Set((opts.riddleAnswers || []).map(row => row.badge_key));

  return `
    <div class="member-badge-grid">
      ${visibleBadges.map(row => {
        const badge = row.badge_catalog || {};
        const imageUrl = getBadgeImageUrl(badge);
        const backImageUrl = getBadgeBackImageUrl(badge);
        const title = badgeDisplayTitle(row);
        const awardedAt = row.awarded_at ? formatDate(row.awarded_at) : '已获得';
        return `
          <button
            type="button"
            class="member-badge-card"
            data-action="member-badge-preview"
            data-badge-title="${esc(title)}"
            data-badge-date="${esc(awardedAt)}"
            data-badge-key="${esc(row.badge_key)}"
            data-badge-image="${esc(imageUrl)}"
            data-badge-back-image="${esc(backImageUrl)}"
            data-badge-can-answer="${opts.canAnswer ? 'true' : 'false'}"
            data-badge-riddle-solved="${answeredKeys.has(row.badge_key) ? 'true' : 'false'}"
          >
            <div class="member-badge-image">
              ${imageUrl ? `<img src="${safeUrl(imageUrl)}" alt="${esc(title)}">` : '<i data-lucide="badge"></i>'}
            </div>
            <div>
              <h4>${h(title)}</h4>
              <p>${h(awardedAt)}</p>
            </div>
          </button>
        `;
      }).join('')}
    </div>
    ${showMore ? `<a href="#/member/badges" class="btn btn-outline btn-sm member-more-badges">${h(moreText)}</a>` : ''}
  `;
}

function renderSelectableBadgeList(member) {
  const badges = sortBadgesForCatalogOrder(member?.badges || []);
  const selectedKeys = new Set(selectedDisplayBadgeKeys(member));
  const answeredKeys = new Set((member?.riddleAnswers || []).map(row => row.badge_key));

  if (!badges.length) {
    return `
      <div class="member-empty-inline">
        <i data-lucide="badge"></i>
        <p>还没有可展示的徽章。</p>
      </div>
    `;
  }

  return `
    <form id="badge-display-form">
      <div class="member-badge-select-toolbar">
        <span data-role="badge-selection-count">已选择 ${h(selectedKeys.size)} / 6</span>
      </div>
      <div class="member-badge-grid">
        ${badges.map(row => {
          const badge = row.badge_catalog || {};
          const imageUrl = getBadgeImageUrl(badge);
          const backImageUrl = getBadgeBackImageUrl(badge);
          const title = badgeDisplayTitle(row);
          const awardedAt = row.awarded_at ? formatDate(row.awarded_at) : '已获得';
          const isFounder = row.badge_key === 'founder' || row.badge_type === 'founder';
          const checked = isFounder || selectedKeys.has(row.badge_key);
          const disabled = isFounder || (!checked && selectedKeys.size >= 6);
          return `
            <div class="member-badge-card member-badge-select-card">
              <input
                type="checkbox"
                id="badge-select-${esc(row.badge_key)}"
                name="badge_display"
                value="${esc(row.badge_key)}"
                ${checked ? 'checked' : ''}
                ${disabled ? 'disabled' : ''}
                ${isFounder ? 'data-fixed="true"' : ''}
              >
              <button
                type="button"
                class="member-badge-image member-badge-preview-trigger"
                data-action="member-badge-preview"
                data-badge-title="${esc(title)}"
                data-badge-date="${esc(awardedAt)}"
                data-badge-key="${esc(row.badge_key)}"
                data-badge-image="${esc(imageUrl)}"
                data-badge-back-image="${esc(backImageUrl)}"
                data-badge-can-answer="true"
                data-badge-riddle-solved="${answeredKeys.has(row.badge_key) ? 'true' : 'false'}"
              >
                ${imageUrl ? `<img src="${safeUrl(imageUrl)}" alt="${esc(title)}">` : '<i data-lucide="badge"></i>'}
              </button>
              <label for="badge-select-${esc(row.badge_key)}">
                <h4>${h(title)}</h4>
                <p>${h(awardedAt)}</p>
              </label>
            </div>
          `;
        }).join('')}
      </div>
      <div class="member-badge-save-row">
        <button type="submit" class="btn btn-primary">保存展示徽章</button>
      </div>
    </form>
  `;
}

function renderCurrentBadge(member) {
  const currentBadge = member?.badges?.find(row => row.badge_key === member?.stats?.current_badge_key)?.badge_catalog || null;
  const imageUrl = getBadgeImageUrl(currentBadge);
  if (imageUrl) {
    return `<img src="${safeUrl(imageUrl)}" alt="${esc(currentBadge.title)}">`;
  }
  return '<i data-lucide="sparkles"></i>';
}

function updateBadgeSelectionState(form) {
  if (!form) return;
  const boxes = [...form.querySelectorAll('input[name="badge_display"]')];
  const checked = boxes.filter(box => box.checked || box.dataset.fixed === 'true');
  const count = checked.length;
  const countEl = form.querySelector('[data-role="badge-selection-count"]');
  if (countEl) countEl.textContent = `已选择 ${count} / 6`;

  boxes.forEach(box => {
    if (box.dataset.fixed === 'true') {
      box.checked = true;
      box.disabled = true;
      return;
    }
    box.disabled = !box.checked && count >= 6;
  });
}

async function saveBadgeDisplayPreferences(form) {
  const user = store.get('user');
  if (!user) return;

  const boxes = [...form.querySelectorAll('input[name="badge_display"]')];
  const keys = boxes
    .filter(box => box.checked || box.dataset.fixed === 'true')
    .map(box => box.value)
    .slice(0, 6);
  const requiredCount = Math.min(6, boxes.length);

  if (keys.length !== requiredCount) {
    toast(`请选择 ${requiredCount} 枚徽章。`, 'error');
    return;
  }

  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) submitBtn.disabled = true;

  const { error: deleteError } = await sb
    .from('member_badge_display_preferences')
    .delete()
    .eq('user_id', user.id);

  if (deleteError) {
    toast('保存失败：请先部署 v10 徽章展示偏好 SQL。', 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  const rows = keys.map((badgeKey, index) => ({
    user_id: user.id,
    badge_key: badgeKey,
    sort_order: index + 1
  }));

  const { error: insertError } = await sb
    .from('member_badge_display_preferences')
    .insert(rows);

  if (insertError) {
    toast('保存失败：' + insertError.message, 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  await loadMemberSummary(user.id);
  toast('展示徽章已保存');
  if (submitBtn) submitBtn.disabled = false;
}

function renderBadgeRiddlePanel({ badgeKey, canAnswer, solved }) {
  const riddle = getBadgeRiddle(badgeKey);
  if (!riddle) return '';

  const lines = riddle.lines.map(line => `<span>${h(line)}</span>`).join('');
  const answerHtml = solved
    ? '<div class="badge-riddle-solved"><i data-lucide="check-circle-2"></i><span>已答对，贡献值奖励已领取</span></div>'
    : canAnswer
      ? `
        <form class="badge-riddle-form" data-badge-key="${esc(badgeKey)}">
          <label for="badge-riddle-answer-${esc(badgeKey)}">输入答案</label>
          <div>
            <input
              id="badge-riddle-answer-${esc(badgeKey)}"
              name="answer"
              type="text"
              autocomplete="off"
              placeholder="写出作者或作品关键词"
              maxlength="80"
              required
            >
            <button type="submit" class="btn btn-primary btn-sm">提交</button>
          </div>
          <p data-role="badge-riddle-feedback">答对奖励 10 贡献值；答错不扣分。</p>
        </form>
      `
      : '<p class="badge-riddle-note">在自己的会员中心答对后，可领取 10 贡献值。</p>';

  return `
    <div class="badge-riddle-panel">
      <div class="badge-riddle-title">
        <i data-lucide="sparkles"></i>
        <span>成就谜面</span>
      </div>
      <div class="badge-riddle-poem">${lines}</div>
      ${answerHtml}
    </div>
  `;
}

async function submitBadgeRiddleAnswer(form) {
  const badgeKey = form.dataset.badgeKey || '';
  const input = form.querySelector('input[name="answer"]');
  const feedback = form.querySelector('[data-role="badge-riddle-feedback"]');
  const submitBtn = form.querySelector('button[type="submit"]');
  const answer = input?.value?.trim() || '';

  if (!badgeKey || !answer) return;

  if (submitBtn) submitBtn.disabled = true;
  if (feedback) feedback.textContent = '正在核对答案...';

  const { data, error } = await sb.rpc('submit_badge_riddle_answer', {
    p_badge_key: badgeKey,
    p_answer: answer
  });

  if (error) {
    const missingRpc = /submit_badge_riddle_answer/i.test(error.message || '');
    if (feedback) feedback.textContent = missingRpc
      ? '请先部署 v31 徽章谜面答题 SQL。'
      : `提交失败：${error.message}`;
    toast(missingRpc ? '请先部署 v31 徽章谜面答题 SQL。' : `提交失败：${error.message}`, 'error');
    if (submitBtn) submitBtn.disabled = false;
    return;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (result?.correct || result?.already_solved) {
    document.querySelectorAll('[data-badge-key]').forEach(el => {
      if (el.dataset.badgeKey === badgeKey) el.dataset.badgeRiddleSolved = 'true';
    });
    form.outerHTML = '<div class="badge-riddle-solved"><i data-lucide="check-circle-2"></i><span>已答对，贡献值奖励已领取</span></div>';
    lucide.createIcons();
    const user = store.get('user');
    if (user) await loadMemberSummary(user.id);
    toast(result?.message || '答对了，已增加 10 贡献值');
    return;
  }

  if (feedback) feedback.textContent = result?.message || '答案还不对，可以再试一次。';
  if (submitBtn) submitBtn.disabled = false;
}

export function openBadgePreview(button) {
  const title = button.dataset.badgeTitle || '徽章';
  const date = button.dataset.badgeDate || '';
  const badgeKey = button.dataset.badgeKey || '';
  const imageUrl = button.dataset.badgeImage || '';
  const backImageUrl = button.dataset.badgeBackImage || '';
  if (!imageUrl) return;
  const canFlip = !!backImageUrl;
  const canAnswer = button.dataset.badgeCanAnswer === 'true';
  const solved = button.dataset.badgeRiddleSolved === 'true';

  document.querySelector('.badge-preview-overlay')?.remove();
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay badge-preview-overlay';
  overlay.innerHTML = `
    <div class="modal badge-preview-modal" role="dialog" aria-modal="true" aria-label="${esc(title)}">
      <button type="button" class="badge-preview-close" data-action="badge-preview-close" aria-label="关闭">
        <i data-lucide="x"></i>
      </button>
      <button type="button" class="badge-flip-stage ${canFlip ? 'can-flip' : ''}" data-action="badge-preview-flip" ${canFlip ? '' : 'disabled'} aria-label="${canFlip ? '翻转徽章' : '徽章预览'}">
        <span class="badge-flip-inner">
          <span class="badge-flip-face badge-flip-front">
            <img src="${safeUrl(imageUrl)}" alt="${esc(title)}正面">
          </span>
          ${canFlip ? `
            <span class="badge-flip-face badge-flip-back">
              <img src="${safeUrl(backImageUrl)}" alt="${esc(title)}背面">
            </span>
          ` : ''}
        </span>
      </button>
      <div class="badge-preview-caption">
        <h3>${h(title)}</h3>
        <p>${h(date)}</p>
        ${canFlip ? '<p class="badge-preview-hint">点击徽章翻转查看背面</p>' : ''}
      </div>
      ${renderBadgeRiddlePanel({ badgeKey, canAnswer, solved })}
    </div>
  `;
  document.body.appendChild(overlay);
  lucide.createIcons();
}

export function bindMemberCenterEvents() {
  document.addEventListener('change', e => {
    const checkbox = e.target.closest('input[name="badge_display"]');
    if (checkbox) updateBadgeSelectionState(checkbox.closest('#badge-display-form'));
  });

  document.addEventListener('submit', async e => {
    if (e.target.id === 'badge-display-form') {
      e.preventDefault();
      await saveBadgeDisplayPreferences(e.target);
      return;
    }
    if (e.target.classList.contains('badge-riddle-form')) {
      e.preventDefault();
      await submitBadgeRiddleAnswer(e.target);
      return;
    }
    if (e.target.id === 'member-library-item-form') {
      e.preventDefault();
      await submitMemberLibraryItem(e.target);
    }
  });

  document.addEventListener('click', async e => {
    const logoutBtn = e.target.closest('#member-logout-btn');
    if (logoutBtn) {
      signOut();
      return;
    }

    const badgeButton = e.target.closest('[data-action="member-badge-preview"]');
    if (badgeButton) {
      openBadgePreview(badgeButton);
      return;
    }

    if (e.target.closest('[data-action="badge-preview-close"]') || e.target.classList.contains('badge-preview-overlay')) {
      document.querySelector('.badge-preview-overlay')?.remove();
      return;
    }

    const flipBtn = e.target.closest('[data-action="badge-preview-flip"]');
    if (flipBtn && !flipBtn.disabled) {
      flipBtn.classList.toggle('is-flipped');
      return;
    }

    const libraryEditBtn = e.target.closest('[data-action="member-library-edit"]');
    if (libraryEditBtn) {
      showMemberLibraryItemModal(libraryEditBtn.dataset.listType, libraryEditBtn.dataset.sortOrder);
      return;
    }

    const libraryFetchBtn = e.target.closest('[data-action="member-library-fetch-book"]');
    if (libraryFetchBtn) {
      const form = libraryFetchBtn.closest('#member-library-item-form');
      if (!form) return;
      libraryFetchBtn.disabled = true;
      try {
        await fetchMemberLibraryBookMeta(form);
      } catch (err) {
        toast('抓取失败：' + (err.message || '未知错误'), 'error');
      } finally {
        libraryFetchBtn.disabled = false;
      }
      return;
    }

    const libraryDeleteBtn = e.target.closest('[data-action="member-library-delete"]');
    if (libraryDeleteBtn) {
      await deleteMemberLibraryItem(libraryDeleteBtn);
    }
  });

  updateBadgeSelectionState(document.getElementById('badge-display-form'));
}

export function registerMemberCenterRoutes() {
  route('/member', async () => {
    const user = store.get('user');
    const profile = store.get('profile');
    if (!user || !profile) {
      return '<div class="container section"><div class="empty-state"><i data-lucide="loader"></i><p>加载中...</p></div></div>';
    }

    const member = await loadMemberSummary(user.id);
    const stats = member?.stats;
    const currentLevel = member?.currentLevel || {
      level: stats?.level || 0,
      title: '基础会员',
      tier: '基础会员',
      min_contribution: 0
    };
    const weeklyRankText = member?.weeklyRank?.rank_position
      ? `当前周贡献排名 第 ${member.weeklyRank.rank_position} 名`
      : '';

    return `
      <div class="container section member-center">
        <div class="member-heading">
          <div class="member-heading-profile">
            <div class="member-avatar">
              ${profile.avatar_url ? `<img src="${safeUrl(profile.avatar_url)}" alt="">` : h((profile.display_name || user.email || '?')[0].toUpperCase())}
            </div>
            <div>
              <p class="member-eyebrow">会员中心</p>
              <h1>${h(profile.display_name || user.email)}</h1>
              <p>${h(currentLevel.tier || '基础会员')} · Lv.${h(currentLevel.level)} ${h(currentLevel.title || '基础会员')}</p>
            </div>
          </div>
          <div class="member-heading-actions">
            <a href="#/user/${h(user.id)}" class="btn btn-outline"><i data-lucide="user"></i> 个人主页</a>
            <a href="#/member/friends" class="btn btn-outline"><i data-lucide="users"></i> 我的好友</a>
            <a href="#/member/library" class="btn btn-outline"><i data-lucide="library"></i> 我的书库</a>
            <button type="button" class="btn btn-outline btn-sm" id="member-logout-btn" style="color:var(--color-danger);border-color:var(--color-danger);"><i data-lucide="log-out"></i> 退出</button>
          </div>
        </div>

        <section class="member-overview">
          <div class="member-current-card">
            <div class="member-current-badge">${renderCurrentBadge(member)}</div>
            <div class="member-current-copy">
              <span>当前等级</span>
              <h2>Lv.${h(currentLevel.level)} ${h(currentLevel.title || '基础会员')}</h2>
              <p>${h(currentLevel.tier || '基础会员')}</p>
            </div>
          </div>
          <div class="member-progress-panel">
            ${renderProgress(stats, currentLevel, member?.nextLevel)}
          </div>
        </section>

        <section class="member-stats-grid">
          ${renderStat('总贡献值', stats?.contribution_total || 0, 'sparkles')}
          ${renderStat('本周贡献值', stats?.contribution_week || 0, 'trending-up', weeklyRankText)}
          ${renderStat('可用资源浏览券', member?.availableViewPasses || 0, 'ticket')}
          ${renderStat('可用共读兑换券', member?.availableRedemptionTickets || 0, 'book-open')}
        </section>

        <div class="member-main-grid">
          <section class="card member-panel member-badges-panel">
            <div class="card-body">
              <div class="member-panel-head">
                <h3>我的徽章</h3>
                <span>${h(member?.badges?.length || 0)} 枚</span>
              </div>
              ${renderBadgeList(displayBadgesForMember(member), {
                limit: 6,
                showMore: true,
                totalCount: member?.badges?.length || 0,
                preserveOrder: true,
                riddleAnswers: member?.riddleAnswers || [],
                canAnswer: true
              })}
            </div>
          </section>

          <section class="card member-panel member-tickets-panel">
            <div class="card-body">
              <div class="member-panel-head">
                <h3>我的票券</h3>
              </div>
              ${renderTicketSummary(member)}
            </div>
          </section>

          <section class="card member-panel member-unlocked-panel">
            <div class="card-body">
              <div class="member-panel-head">
                <h3>已解锁资源</h3>
                <span>${h(member?.accessGrants?.length || 0)} 项</span>
              </div>
              ${renderAccessGrants(member)}
            </div>
          </section>

        </div>
      </div>
    `;
  });

  route('/member/library', async () => {
    memberLibraryItemCache.clear();
    const active = activeLibraryTab();
    const { finishedBooks, items, error } = await loadMemberLibrary();
    if (error) return renderMemberLibraryError(error);

    return `
      <div class="container section member-library-page">
        <div class="member-heading">
          <div>
            <p class="member-eyebrow">会员中心</p>
            <h1>我的书库</h1>
            <p>整理你的已读、想读，以及愿意郑重推荐给他人的人生之书。</p>
          </div>
          <a href="#/member" class="btn btn-outline"><i data-lucide="arrow-left"></i> 返回个人中心</a>
        </div>

        ${renderLibraryTabs(active)}

        <section class="card member-panel">
          <div class="card-body">
            ${active === 'finished' ? renderFinishedLibrary(finishedBooks) : renderEditableLibrary(active, items)}
          </div>
        </section>
      </div>
    `;
  });

  route('/member/badges', async () => {
    const user = store.get('user');
    if (!user) return '';
    const member = await loadMemberSummary(user.id);
    return `
      <div class="container section member-center">
        <div class="member-heading">
          <div>
            <p class="member-eyebrow">会员中心</p>
            <h1>全部徽章</h1>
            <p>共 ${h(member?.badges?.length || 0)} 枚</p>
          </div>
          <a href="#/member" class="btn btn-outline"><i data-lucide="arrow-left"></i> 返回个人中心</a>
        </div>
        <section class="card member-panel">
          <div class="card-body">
            ${renderSelectableBadgeList(member)}
          </div>
        </section>
      </div>
    `;
  });

  route('/member/tickets', async () => {
    const user = store.get('user');
    if (!user) return '';
    const member = await loadMemberSummary(user.id);
    const summary = ticketSummary(member);
    return `
      <div class="container section member-center">
        <div class="member-heading">
          <div>
            <p class="member-eyebrow">会员中心</p>
            <h1>我的票券</h1>
            <p>资源浏览券 ${h(summary.availableViewPasses)} 可用 / ${h(summary.unavailableViewPasses)} 不可用，共读兑换券 ${h(summary.availableRedemptionTickets)} 可用 / ${h(summary.unavailableRedemptionTickets)} 不可用</p>
          </div>
          <a href="#/member" class="btn btn-outline"><i data-lucide="arrow-left"></i> 返回个人中心</a>
        </div>

        <div class="member-ticket-page-grid">
          <section class="card member-panel">
            <div class="card-body">
              <div class="member-panel-head">
                <h3>资源浏览券</h3>
                <span>${h(summary.viewPasses.length)} 张</span>
              </div>
              ${renderTicketRows('view', summary.viewPasses)}
            </div>
          </section>

          <section class="card member-panel">
            <div class="card-body">
              <div class="member-panel-head">
                <h3>共读兑换券</h3>
                <span>${h(summary.redemptionTickets.length)} 张</span>
              </div>
              ${renderTicketRows('redemption', summary.redemptionTickets)}
            </div>
          </section>
        </div>
      </div>
    `;
  });
}
