import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';

if (typeof supabase === 'undefined') {
  console.error('Supabase CDN 加载失败');
}

const { createClient } = supabase;

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
