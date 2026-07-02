-- ============================================================
-- 以读攻独 · v38 迁移：共读导言增加标题/副标题/作者字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_title TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_subtitle TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS host_notes_author TEXT;
