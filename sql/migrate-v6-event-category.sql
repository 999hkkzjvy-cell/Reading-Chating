-- 以读攻独 · v6 迁移：活动分类 + 活动链接
-- 在 Supabase SQL Editor 中执行

ALTER TABLE events ADD COLUMN IF NOT EXISTS category TEXT DEFAULT '其他';
ALTER TABLE events ADD COLUMN IF NOT EXISTS link TEXT;
