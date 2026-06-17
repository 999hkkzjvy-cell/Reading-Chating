-- ============================================================
-- 以读攻独 · 数据库迁移 v1 → v2
-- 在 Supabase SQL Editor 中执行（对已有数据库）
-- 警告：执行前请备份数据库！
-- ============================================================

-- 1. 新增字段（全部 nullable，不影响现有数据）
ALTER TABLE books ADD COLUMN IF NOT EXISTS author_country TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS author_gender TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS translator_gender TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS word_count INTEGER;
ALTER TABLE books ADD COLUMN IF NOT EXISTS author_bio TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS historical_context TEXT;
ALTER TABLE books ADD COLUMN IF NOT EXISTS host_notes TEXT;

-- 2. 迁移 edition_guide：备份旧 MD 列，新建 JSONB 列
ALTER TABLE books RENAME COLUMN edition_guide TO edition_guide_md;
ALTER TABLE books ADD COLUMN IF NOT EXISTS edition_guide JSONB DEFAULT '[]';

-- 3. 合并 meeting_replays 到 online_activities，再改名为 activities
DO $$
DECLARE
  book_record RECORD;
  merged JSONB;
  replay_item JSONB;
  new_activity JSONB;
BEGIN
  FOR book_record IN
    SELECT id, online_activities, meeting_replays FROM books
  LOOP
    merged := COALESCE(book_record.online_activities, '[]'::JSONB);

    -- 把每个回放转成活动
    IF book_record.meeting_replays IS NOT NULL
       AND book_record.meeting_replays != '[]'::JSONB THEN
      FOR replay_item IN
        SELECT * FROM jsonb_array_elements(book_record.meeting_replays)
      LOOP
        new_activity := jsonb_build_object(
          'type', '其他',
          'title', replay_item->>'title',
          'time', replay_item->>'date',
          'status', '已完结',
          'meeting_link', '',
          'replay_link', replay_item->>'url',
          'guests', '',
          'description', COALESCE(replay_item->>'platform', '')
        );
        merged := merged || new_activity;
      END LOOP;
    END IF;

    UPDATE books SET online_activities = merged WHERE id = book_record.id;
  END LOOP;
END $$;

-- 4. 重命名 online_activities → activities
ALTER TABLE books RENAME COLUMN online_activities TO activities;

-- 5. 清理旧列
ALTER TABLE books DROP COLUMN IF EXISTS isbn;
ALTER TABLE books DROP COLUMN IF EXISTS page_count;
ALTER TABLE books DROP COLUMN IF EXISTS meeting_replays;

-- 6. 修改 genre 默认值（可选）
ALTER TABLE books ALTER COLUMN genre SET DEFAULT '文学';

-- ============================================================
-- 创建封面图 Storage bucket
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('covers', 'covers', true)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies
DROP POLICY IF EXISTS "covers_read_all" ON storage.objects;
CREATE POLICY "covers_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'covers');

DROP POLICY IF EXISTS "covers_admin_insert" ON storage.objects;
CREATE POLICY "covers_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

DROP POLICY IF EXISTS "covers_admin_update" ON storage.objects;
CREATE POLICY "covers_admin_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

DROP POLICY IF EXISTS "covers_admin_delete" ON storage.objects;
CREATE POLICY "covers_admin_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'covers' AND EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));

-- ============================================================
-- 迁移完成！
-- 旧 edition_guide 内容保留在 edition_guide_md 列中
-- 可之后手动迁移到新 JSONB 格式，确认无误后执行：
--   ALTER TABLE books DROP COLUMN edition_guide_md;
-- ============================================================
