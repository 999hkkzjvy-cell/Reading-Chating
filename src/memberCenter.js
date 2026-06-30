import { loadMemberSummary } from './members.js';
import { route } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { esc, formatDate, formatDateTime, h, safeUrl } from './utils.js';

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
            data-badge-image="${esc(imageUrl)}"
            data-badge-back-image="${esc(backImageUrl)}"
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
                data-badge-image="${esc(imageUrl)}"
                data-badge-back-image="${esc(backImageUrl)}"
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

export function openBadgePreview(button) {
  const title = button.dataset.badgeTitle || '徽章';
  const date = button.dataset.badgeDate || '';
  const imageUrl = button.dataset.badgeImage || '';
  const backImageUrl = button.dataset.badgeBackImage || '';
  if (!imageUrl) return;
  const canFlip = !!backImageUrl;

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
    }
  });

  document.addEventListener('click', e => {
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
            <button class="btn btn-outline btn-sm" id="member-logout-btn" style="color:var(--color-danger);border-color:var(--color-danger);"><i data-lucide="log-out"></i> 退出</button>
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
                preserveOrder: true
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

  route('/member/library', () => `
    <div class="container section">
      <div class="empty-state">
        <i data-lucide="library"></i>
        <p>我的书库将在后续阶段开放</p>
      </div>
    </div>
  `);

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
