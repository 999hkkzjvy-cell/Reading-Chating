-- 以读攻独 · 迁移 v45：books 表新增 xuxu_notes（灵沁碎碎念）字段
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS xuxu_notes TEXT;