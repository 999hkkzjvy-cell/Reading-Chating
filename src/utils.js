import { SUPABASE_URL } from './config.js';

marked.setOptions({ breaks: false, gfm: true });

export function safeMarked(text) {
  return DOMPurify.sanitize(marked.parse(text || ''));
}

export function h(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function esc(s) {
  return h(s).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

export function safeUrl(u) {
  u = String(u || '').trim();
  return /^(https?:|mailto:|\/|#)/i.test(u) ? esc(u) : '#';
}

export function parseHttpUrl(u) {
  try {
    const parsed = new URL(String(u || '').trim());
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed : null;
  } catch (e) {
    return null;
  }
}

export function isDoubanBookUrl(u) {
  const parsed = parseHttpUrl(u);
  if (!parsed) return false;
  // 桌面版：book.douban.com/subject/1234567/
  if (parsed.hostname === 'book.douban.com' && parsed.pathname.startsWith('/subject/')) return true;
  // 移动端分享链接：www.douban.com/doubanapp/dispatch/book/12345678
  if (parsed.hostname === 'www.douban.com' && /^\/doubanapp\/dispatch\/book\/\d+/.test(parsed.pathname)) return true;
  return false;
}

export function normalizeDoubanBookUrl(u) {
  const parsed = parseHttpUrl(u);
  if (!parsed) return u;
  // 移动端 → 桌面版
  const m = parsed.pathname.match(/^\/doubanapp\/dispatch\/book\/(\d+)/);
  if (m && parsed.hostname === 'www.douban.com') {
    return `https://book.douban.com/subject/${m[1]}/`;
  }
  return u;
}

function isDoubanioImageUrl(u) {
  const parsed = parseHttpUrl(u);
  if (!parsed) return false;
  const host = parsed.hostname.toLowerCase();
  return host === 'doubanio.com' || host.endsWith('.doubanio.com');
}

export function safeColor(c, fallback = 'transparent') {
  c = String(c || '').trim();
  return /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c) ? c : fallback;
}

export function proxyImg(url) {
  if (!url) return '';
  if (isDoubanioImageUrl(url)) {
    return SUPABASE_URL + '/functions/v1/img-proxy?url=' + encodeURIComponent(url);
  }
  return url;
}

export function formatDate(d) {
  if (!d) return '';
  return dayjs(d).format('YYYY年M月D日');
}

export function formatDateTime(d) {
  if (!d) return '';
  return dayjs(d).format('YYYY年M月D日 HH:mm');
}
