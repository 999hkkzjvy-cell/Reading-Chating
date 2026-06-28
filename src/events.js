import { statusTag } from './components.js';
import { STATUS_CLASS, STATUS_MAP } from './constants.js';
import { loadEvents } from './data.js';
import { route } from './router.js';
import { sb } from './supabaseClient.js';
import { formatDateTime, h, safeMarked, safeUrl } from './utils.js';

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

