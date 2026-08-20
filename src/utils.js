import { SUPABASE_URL } from './config.js';

marked.setOptions({ breaks: false, gfm: true });

// Project-wide time convention: user-facing dates and date-time inputs are
// always interpreted and displayed in Beijing time, regardless of device TZ.
export const PROJECT_TIME_ZONE = 'Asia/Shanghai';

const BEIJING_PARTS_FORMATTER = new Intl.DateTimeFormat('en-US', {
  timeZone: PROJECT_TIME_ZONE,
  calendar: 'gregory',
  numberingSystem: 'latn',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23'
});

function parseInstant(value) {
  if (value instanceof Date) {
    const copy = new Date(value.getTime());
    return Number.isNaN(copy.getTime()) ? null : copy;
  }

  if (typeof value === 'number') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  const text = String(value ?? '').trim();
  if (!text) return null;

  // Timestamp values from Supabase normally include an explicit offset. For
  // legacy no-offset values, use the project's UTC storage convention rather
  // than letting the browser silently apply its own local timezone.
  const noOffsetMatch = text.match(/^(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?)?$/);
  const date = noOffsetMatch
    ? new Date(`${noOffsetMatch[1]}T${noOffsetMatch[2] || '00:00'}:${noOffsetMatch[3] || '00'}${noOffsetMatch[4] ? `.${noOffsetMatch[4]}` : ''}Z`)
    : new Date(text);
  return Number.isNaN(date.getTime()) ? null : date;
}

function beijingParts(value) {
  const date = parseInstant(value);
  if (!date) return null;
  return Object.fromEntries(
    BEIJING_PARTS_FORMATTER.formatToParts(date)
      .filter(part => part.type !== 'literal')
      .map(part => [part.type, part.value])
  );
}

export function getBeijingDateKey(value) {
  const parts = beijingParts(value);
  return parts ? `${parts.year}-${parts.month}-${parts.day}` : '';
}

export function getTimestamp(value) {
  const date = parseInstant(value);
  return date ? date.getTime() : NaN;
}

export function getBeijingCalendarContext(value = new Date()) {
  const parts = beijingParts(value);
  if (!parts) return null;

  const year = Number(parts.year);
  const month = Number(parts.month);
  const day = Number(parts.day);
  const firstDayUtc = Date.UTC(year, month - 1, 1);
  return {
    year,
    month,
    day,
    todayKey: `${parts.year}-${parts.month}-${parts.day}`,
    monthPrefix: `${parts.year}-${parts.month}`,
    daysInMonth: new Date(Date.UTC(year, month, 0)).getUTCDate(),
    startDayOfWeek: new Date(firstDayUtc).getUTCDay(),
    prevMonthDays: new Date(Date.UTC(year, month - 1, 0)).getUTCDate()
  };
}

export function formatDateCompact(d) {
  const parts = beijingParts(d);
  return parts ? `${parts.year}.${parts.month}.${parts.day}` : '';
}

export function formatDateTimeLocal(d) {
  const parts = beijingParts(d);
  return parts ? `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}` : '';
}

export function formatDateTimeFilename(d = new Date()) {
  const parts = beijingParts(d);
  return parts ? `${parts.year}${parts.month}${parts.day}-${parts.hour}${parts.minute}` : '';
}

export function toBeijingISOString(value) {
  const text = String(value ?? '').trim();
  if (!text) return null;

  const explicitOffset = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(text);
  const normalized = explicitOffset
    ? text
    : `${text.length === 16 ? `${text}:00` : text}+08:00`;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

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
  const parts = beijingParts(d);
  return parts ? `${Number(parts.year)}年${Number(parts.month)}月${Number(parts.day)}日` : '';
}

export function formatDateTime(d) {
  const parts = beijingParts(d);
  return parts ? `${Number(parts.year)}年${Number(parts.month)}月${Number(parts.day)}日 ${parts.hour}:${parts.minute}` : '';
}
