-- ============================================================
-- 以读攻独 · v28 迁移：徽章背面图
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.badge_catalog
  ADD COLUMN IF NOT EXISTS back_image_bucket TEXT NOT NULL DEFAULT 'badges';

ALTER TABLE public.badge_catalog
  ADD COLUMN IF NOT EXISTS back_image_path TEXT;

COMMENT ON COLUMN public.badge_catalog.back_image_bucket IS
  '徽章背面图片所在 Supabase Storage bucket';

COMMENT ON COLUMN public.badge_catalog.back_image_path IS
  '徽章背面图片在 bucket 内的路径；为空时预览不启用翻面';
