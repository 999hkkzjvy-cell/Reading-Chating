-- ============================================================
-- 以读攻独 · 数据库迁移 v46 — 新书速递保留豆瓣源顺序
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.douban_new_books
  ADD COLUMN IF NOT EXISTS source_rank INTEGER,
  ADD COLUMN IF NOT EXISTS source_page INTEGER;

CREATE INDEX IF NOT EXISTS idx_dnb_latest_source_order
  ON public.douban_new_books(scraped_at DESC, source_rank ASC);
