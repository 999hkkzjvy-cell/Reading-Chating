import { SUPABASE_URL } from './config.js';
import { sb } from './supabaseClient.js';
import { store } from './store.js';
import { toast } from './ui.js';

export async function loadBooks() {
  const { data } = await sb.from('books').select('*').order('start_date', { ascending: false, nullsFirst: false });
  store.set('books', data || []);
  return data || [];
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

export async function getTodayCheckin() {
  const user = store.get('user');
  if (!user) return false;
  const today = dayjs().format('YYYY-MM-DD');
  const { data } = await sb.from('daily_checkins').select('*').eq('user_id', user.id).eq('checkin_date', today).maybeSingle();
  return !!data;
}

export async function getMonthCheckinsFull(year, month) {
  const user = store.get('user');
  if (!user) return [];
  const start = dayjs(`${year}-${String(month).padStart(2, '0')}-01`).format('YYYY-MM-DD');
  const end = dayjs(start).endOf('month').format('YYYY-MM-DD');
  const { data } = await sb.from('daily_checkins').select('checkin_date, mood_color, excerpt, reflection, book_title').eq('user_id', user.id).gte('checkin_date', start).lte('checkin_date', end);
  return data || [];
}

export async function doCheckin(payload) {
  const user = store.get('user');
  if (!user) {
    toast('请先登录', 'error');
    return false;
  }
  const today = dayjs().format('YYYY-MM-DD');
  const { error } = await sb.from('daily_checkins').insert({
    user_id: user.id,
    checkin_date: today,
    book_title: payload.book_title || null,
    excerpt: payload.excerpt || null,
    reflection: payload.reflection || null,
    mood_color: payload.mood_color || null
  });
  if (error) {
    if (error.code === '23505') {
      toast('今天已经签到过了，请使用编辑功能', 'error');
    } else {
      toast('签到失败：' + error.message, 'error');
    }
    return false;
  }
  toast('签到成功！今天又读了一点 📖');
  return true;
}

export async function updateCheckin(dateStr, payload) {
  const user = store.get('user');
  if (!user) {
    toast('请先登录', 'error');
    return false;
  }
  const { error } = await sb.from('daily_checkins').update({
    book_title: payload.book_title || null,
    excerpt: payload.excerpt || null,
    reflection: payload.reflection || null,
    mood_color: payload.mood_color || null
  }).eq('user_id', user.id).eq('checkin_date', dateStr);
  if (error) {
    toast('更新失败：' + error.message, 'error');
    return false;
  }
  toast('签到已更新 📝');
  return true;
}

export async function getCheckinDetail(dateStr) {
  const user = store.get('user');
  if (!user) return null;
  const { data } = await sb.from('daily_checkins').select('*').eq('user_id', user.id).eq('checkin_date', dateStr).maybeSingle();
  return data;
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
