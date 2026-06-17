-- ============================================================
-- 以读攻独 · 数据库迁移 v3 — 增强签到功能
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 新增签到字段
ALTER TABLE daily_checkins ADD COLUMN IF NOT EXISTS book_title TEXT;
ALTER TABLE daily_checkins ADD COLUMN IF NOT EXISTS excerpt TEXT;
ALTER TABLE daily_checkins ADD COLUMN IF NOT EXISTS reflection TEXT;
ALTER TABLE daily_checkins ADD COLUMN IF NOT EXISTS mood_color TEXT;

-- 2. 允许用户编辑自己的签到
DROP POLICY IF EXISTS "checkins_update_self" ON daily_checkins;
CREATE POLICY "checkins_update_self" ON daily_checkins FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
