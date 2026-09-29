import { SUPABASE_URL } from './config.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';

const BOOK_LIST_COLUMNS = [
  'id', 'title', 'author', 'author_country', 'cover_url', 'status', 'genre', 'start_date', 'end_date'
].join(',');

export async function loadBooks({ forAdmin = false } = {}) {
  const { data, error } = await sb
    .from('books')
    .select(forAdmin ? '*' : BOOK_LIST_COLUMNS)
    .order('start_date', { ascending: false, nullsFirst: false });
  if (error) throw error;

  let books = data || [];
  if (forAdmin && books.length) {
    books = await Promise.all(books.map(async book => {
      const { data: protectedContent, error: protectedError } = await sb.rpc('get_book_protected_content', {
        p_book_id: book.id,
        p_section: 'admin',
        p_index: null
      });
      if (protectedError) throw protectedError;
      return { ...book, ...(protectedContent || {}) };
    }));
  }

  if (!forAdmin) store.set('books', books);
  return books;
}

export async function loadBookProtectedContent(bookId, section, index = null) {
  const { data, error } = await sb.rpc('get_book_protected_content', {
    p_book_id: bookId,
    p_section: section,
    p_index: index
  });
  if (error) throw error;
  return data || {};
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
  const { data } = await sb
    .from('site_config')
    .select('key,value')
    .in('key', ['group_rules', 'reading_plan_intro']);
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
