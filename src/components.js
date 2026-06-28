import { STATUS_CLASS, STATUS_MAP } from './constants.js';
import { formatDate, h, safeUrl } from './utils.js';

export function statusTag(s) {
  return `<span class="tag ${STATUS_CLASS[s] || 'tag-upcoming'}">${STATUS_MAP[s] || h(s)}</span>`;
}

export function renderBookCard(b, opts = {}) {
  const { link = true } = opts;
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

export function renderHomeBookCard(b) {
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
