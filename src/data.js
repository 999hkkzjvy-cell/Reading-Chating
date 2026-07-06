import { SUPABASE_URL } from './config.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';

export async function loadBooks() {
  const { data } = await sb.from('books').select('*').order('start_date', { ascending: false, nullsFirst: false });
  store.set('books', data || []);
  return data || [];
}

export async function loadHomeBooks() {
  const columns = [
    'id',
    'title',
    'author',
    'author_country',
    'translator',
    'publisher',
    'cover_url',
    'status',
    'start_date',
    'end_date',
    'description'
  ].join(',');
  const { data } = await sb
    .from('books')
    .select(columns)
    .not('end_date', 'is', null)
    .order('end_date', { ascending: false })
    .limit(2);

  if (data?.length) return data;

  const { data: fallback } = await sb
    .from('books')
    .select(columns)
    .order('start_date', { ascending: false, nullsFirst: false })
    .limit(2);
  return fallback || [];
}

export async function loadEvents() {
  const { data } = await sb.from('events').select('*').order('event_date', { ascending: false });
  store.set('events', data || []);
  return data || [];
}

export async function loadConfig() {
  const { data } = await sb.from('site_config').select('*');
  const config = {};
  (data || []).forEach(r => config[r.key] = r.value);
  store.set('config', config);
  return config;
}

export async function aiFillBookInfo(title, author) {
  if (!title || !author) {
    toast('请先填写书名和作者', 'error');
    return null;
  }

  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    toast('请先登录', 'error');
    return null;
  }

  const edgeUrl = `${SUPABASE_URL}/functions/v1/deepseek-proxy`;

  let response;
  try {
    response = await fetch(edgeUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`
      },
      body: JSON.stringify({ title, author })
    });
  } catch (err) {
    toast('AI 请求失败：网络错误，请检查 Edge Function 是否已部署', 'error');
    return null;
  }

  if (!response.ok) {
    const errData = await response.json().catch(() => ({}));
    toast('AI 请求失败：' + (errData.error || response.status), 'error');
    return null;
  }

  return await response.json();
}
