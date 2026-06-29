import { loadMemberSummary } from './members.js';
import { router } from './router.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { claimCoReadingPassword, consumeViewPass, redeemBookAccess } from './tickets.js';
import { h, safeMarked, safeUrl } from './utils.js';

export function resourceKey(bookId, section, index, field = 'url') {
  return `book:${bookId}:${section}:${index}:${field}`;
}

export function canViewResource(summary, key) {
  return !!summary?.hasPermanentAccess || !!summary?.temporaryResourceKeys?.includes(key);
}

export function renderBookAccessPanel(book, summary) {
  if (!store.get('user')) {
    return `
      <div class="resource-access-panel">
        <i data-lucide="lock"></i>
        <div>
          <strong>共读资源权益</strong>
          <p>登录后可使用资源浏览券临时查看，或用共读兑换券永久解锁本期资源。</p>
        </div>
        <a href="#/login?redirect=/books/${h(book.id)}" class="btn btn-outline btn-sm">登录</a>
      </div>
    `;
  }

  if (summary?.hasPermanentAccess) {
    return `
      <div class="resource-access-panel unlocked">
        <i data-lucide="lock-open"></i>
        <div>
          <strong>已永久解锁</strong>
          <p>你已拥有《${h(book.title)}》本期共读资源的永久浏览权限。</p>
        </div>
      </div>
    `;
  }

  return `
    <div class="resource-access-panel">
      <i data-lucide="lock"></i>
      <div>
        <strong>共读资源权益</strong>
        <p>你有 ${h(summary?.availableViewPasses || 0)} 张资源浏览券、${h(summary?.availableRedemptionTickets || 0)} 张共读兑换券。</p>
      </div>
      ${summary?.availableRedemptionTickets > 0
        ? `<button type="button" class="btn btn-primary btn-sm" data-action="redeem-book-access" data-book-id="${h(book.id)}">永久解锁本书</button>`
        : '<span class="resource-lock-note">每周发放资源浏览券，活跃榜前5名发券翻倍；提升等级可获得共读兑换券，解锁本期共读全部资源。</span>'}
    </div>
  `;
}

function renderUnlockButton(bookId, key, summary, label = '临时解锁') {
  if (!store.get('user')) {
    return `<a href="#/login?redirect=/books/${h(bookId)}" class="btn btn-outline btn-sm">登录查看</a>`;
  }
  if ((summary?.availableViewPasses || 0) <= 0) {
    return '<span class="resource-lock-note">暂无可用资源浏览券</span>';
  }
  return `
    <button type="button" class="btn btn-outline btn-sm"
      data-action="consume-view-pass"
      data-book-id="${h(bookId)}"
      data-resource-key="${h(key)}">${h(label)}</button>
  `;
}

export function renderProtectedLink({ bookId, key, url, label, summary }) {
  if (!url) return '';
  if (canViewResource(summary, key)) {
    return `<a href="${safeUrl(url)}" target="_blank" class="btn btn-outline btn-sm">${h(label)}</a>`;
  }

  return `
    <span class="resource-locked-inline">
      <span><i data-lucide="lock"></i> ${h(label)}</span>
      ${renderUnlockButton(bookId, key, summary)}
    </span>
  `;
}

export function renderProtectedText({ bookId, key, markdown, summary }) {
  if (!markdown) return '';
  if (canViewResource(summary, key)) {
    return `<div class="md-content" style="max-width:none;font-size:0.95rem;">${safeMarked(markdown)}</div>`;
  }

  return `
    <div class="resource-locked-block">
      <i data-lucide="lock"></i>
      <div>
        <strong>完整内容暂未解锁</strong>
        <p>这部分是共读参与权益。你可以使用资源浏览券临时查看 72 小时，或用共读兑换券永久解锁本期资源。</p>
        ${renderUnlockButton(bookId, key, summary, '临时查看正文')}
      </div>
    </div>
  `;
}

export function renderProtectedGroup({ bookId, key, title, description, summary, unlockLabel = '临时解锁' }) {
  if (canViewResource(summary, key)) return '';

  return `
    <div class="resource-locked-block">
      <i data-lucide="lock"></i>
      <div>
        <strong>${h(title)}</strong>
        <p>${h(description)}</p>
        ${renderUnlockButton(bookId, key, summary, unlockLabel)}
      </div>
    </div>
  `;
}

export function bindAccessEvents() {
  document.addEventListener('click', async e => {
    const viewBtn = e.target.closest('[data-action="consume-view-pass"]');
    if (viewBtn) {
      if (!confirm('确定消耗 1 张资源浏览券，临时解锁该资源 72 小时吗？')) return;
      viewBtn.disabled = true;
      const { error } = await consumeViewPass(viewBtn.dataset.bookId, viewBtn.dataset.resourceKey);
      if (error) {
        const message = error.message === 'No available view pass' ? '暂无可用资源浏览券' : error.message;
        toast('解锁失败：' + message, 'error');
        viewBtn.disabled = false;
        return;
      }
      toast('已临时解锁 72 小时');
      await loadMemberSummary(store.get('user')?.id);
      router.render();
      return;
    }

    const redeemBtn = e.target.closest('[data-action="redeem-book-access"]');
    if (redeemBtn) {
      if (!confirm('确定消耗 1 张共读兑换券，永久解锁本书共读资源吗？')) return;
      redeemBtn.disabled = true;
      const { error } = await redeemBookAccess(redeemBtn.dataset.bookId);
      if (error) {
        const message = error.message === 'No available redemption ticket' ? '暂无可用共读兑换券' : error.message;
        toast('兑换失败：' + message, 'error');
        redeemBtn.disabled = false;
        return;
      }
      toast('已永久解锁本书资源');
      await loadMemberSummary(store.get('user')?.id);
      router.render();
      return;
    }

    const claimForm = e.target.closest('[data-action="claim-co-reading-password"]');
    if (claimForm) {
      // Handled by the submit listener below.
      return;
    }
  });

  document.addEventListener('submit', async e => {
    if (e.target.dataset.action !== 'claim-co-reading-password') return;
    e.preventDefault();
    if (!store.get('user')) {
      router.navigate('/login?redirect=' + encodeURIComponent(router.currentPath()));
      return;
    }

    const form = e.target;
    const submitBtn = form.querySelector('button[type="submit"]');
    if (submitBtn) submitBtn.disabled = true;

    const fd = new FormData(form);
    const { error } = await claimCoReadingPassword(
      fd.get('book_id'),
      fd.get('password')?.trim(),
      fd.get('group_member_id')?.trim()
    );

    if (error) {
      const map = {
        'Invalid co-reading password': '共读密码不正确或已过期',
        'Group member id is required': '请填写群内 ID / 昵称'
      };
      toast('核销失败：' + (map[error.message] || error.message), 'error');
      if (submitBtn) submitBtn.disabled = false;
      return;
    }

    toast('核销成功，已解锁本期共读资源');
    await loadMemberSummary(store.get('user')?.id);
    router.render();
  });
}
