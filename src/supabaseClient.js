import { SUPABASE_ANON_KEY, SUPABASE_URL } from './config.js';
import { createDiagnosticFetch } from './authDiagnostics.js';

if (typeof supabase === 'undefined') {
  console.error('Supabase CDN 加载失败');
}

const { createClient } = supabase;

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { fetch: createDiagnosticFetch(new URL(SUPABASE_URL).origin) },
});
