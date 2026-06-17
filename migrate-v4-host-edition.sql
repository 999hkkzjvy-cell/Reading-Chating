-- ============================================================
-- 以读攻独 · 数据库迁移 v4 — 领读人 & 版本建议增强
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 新增字段
ALTER TABLE books ADD COLUMN IF NOT EXISTS host TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS edition_notes TEXT;

-- 2. 清理旧字段
ALTER TABLE books DROP COLUMN IF EXISTS edition_guide_md;
