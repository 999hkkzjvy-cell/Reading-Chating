import { esc, h } from './utils.js';

export const POST_TYPE_LABELS = {
  want: '想读',
  reading: '在读',
  finished: '已读'
};

export const VISIBILITY_LABELS = {
  public: '公开',
  private: '仅自己可见'
};

export const CALENDAR_DAY_NAMES = ['日', '一', '二', '三', '四', '五', '六'];

export function postTypeOptions(selected = 'reading') {
  return Object.entries(POST_TYPE_LABELS).map(([value, label]) => (
    `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${h(label)}</option>`
  )).join('');
}

export function visibilityOptions(selected = 'public') {
  return Object.entries(VISIBILITY_LABELS).map(([value, label]) => (
    `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${h(label)}</option>`
  )).join('');
}

export function formatBookTitle(title) {
  const clean = String(title || '').trim();
  if (!clean) return '';
  return /^《.*》$/.test(clean) ? clean : `《${clean.replace(/^《|》$/g, '')}》`;
}

export function contentLabel(postType) {
  if (postType === 'finished') return '书评';
  return '感想';
}

export function ratingEmoji(score) {
  const n = Number(score);
  if (isNaN(n)) return '';
  if (n < 0) return '💩';
  if (n < 6) return '🤢';
  if (n < 8) return '🙂';
  return '👏🏻';
}
