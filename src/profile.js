import {
  findTodayCheckin,
  getCalendarCheckins,
  getCalendarState,
  moveCalendarMonth,
  refreshCalendar,
  renderCalendarGrid,
  resetCalendarToCurrentMonth,
  showCheckinDetail,
  showCheckinForm
} from './checkins.js';
import { doCheckin, getCheckinDetail, updateCheckin } from './data.js';
import { route, router } from './router.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';
import { esc, h, safeUrl } from './utils.js';

export function registerProfileRoutes() {
  route('/profile', async () => {
    const profile = store.get('profile');
    if (!profile) return '<div class="container section"><div class="empty-state"><i data-lucide="loader"></i><p>加载中...</p></div></div>';

    await resetCalendarToCurrentMonth();
    const { year: calYear, month: calMonth } = getCalendarState();
    const todayCheckin = findTodayCheckin();

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
                  <div class="calendar-grid" id="cal-grid">${renderCalendarGrid()}</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  });

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
}

export function bindProfileEvents() {
  document.addEventListener('submit', async e => {
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
      if (error) {
        toast('保存失败：' + error.message, 'error');
        return;
      }
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

  document.addEventListener('click', async e => {
    const calPrev = e.target.closest('#cal-prev');
    if (calPrev) {
      await moveCalendarMonth(-1);
      return;
    }

    const calNext = e.target.closest('#cal-next');
    if (calNext) {
      await moveCalendarMonth(1);
      return;
    }

    const checkinBtn = e.target.closest('#checkin-btn');
    if (checkinBtn) {
      const today = dayjs().format('YYYY-MM-DD');
      const todayCheckin = getCalendarCheckins().find(c => c.checkin_date === today);
      showCheckinForm(todayCheckin || null);
      return;
    }

    const calDay = e.target.closest('#cal-grid .day.checked');
    if (calDay && calDay.dataset.date) {
      const checkin = await getCheckinDetail(calDay.dataset.date);
      if (checkin) showCheckinDetail(checkin);
      return;
    }

    const editBtn = e.target.closest('#edit-checkin-btn');
    if (editBtn) {
      const checkin = await getCheckinDetail(editBtn.dataset.date);
      if (checkin) {
        const overlay = editBtn.closest('.modal-overlay');
        if (overlay) overlay.remove();
        showCheckinForm(checkin);
      }
    }
  });
}
