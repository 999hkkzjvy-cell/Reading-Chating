-- ============================================================
-- 以读攻独 · 数据库迁移 v4 — 领读人 & 版本建议增强
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 新增字段
ALTER TABLE books ADD COLUMN IF NOT EXISTS host TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS edition_notes TEXT;

-- 2. 清理旧字段
ALTER TABLE books DROP COLUMN IF EXISTS edition_guide_md;

-- 3. reading_schedule 从 TEXT 改为 JSONB（计划简述 + PDF链接）
ALTER TABLE books ADD COLUMN IF NOT EXISTS reading_schedule_new JSONB;
UPDATE books SET reading_schedule_new = jsonb_build_object('summary', COALESCE(reading_schedule, ''), 'pdf_url', '') WHERE reading_schedule_new IS NULL;
ALTER TABLE books DROP COLUMN IF EXISTS reading_schedule;
ALTER TABLE books RENAME COLUMN reading_schedule_new TO reading_schedule;

-- 4. PDF 文件存储 bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('files', 'files', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "files_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'files');
CREATE POLICY "files_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'files' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
