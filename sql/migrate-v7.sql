-- ============================================================
-- 以读攻独 · v7 在 Supabase SQL Editor 中一次性执行
-- ============================================================

-- 1. 资源材料增加"其他"分类
ALTER TABLE books ALTER COLUMN resources SET DEFAULT '{"extended_reading":[],"text_materials":[],"film_resources":[],"other":[]}';

-- 2. 豆瓣书籍缓存表
CREATE TABLE IF NOT EXISTS douban_book_cache (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  douban_url    TEXT UNIQUE NOT NULL,
  title         TEXT,
  cover_url     TEXT,
  author        TEXT,
  translator    TEXT,
  publisher     TEXT,
  rating        TEXT,
  review_count  INTEGER DEFAULT 0,
  description   TEXT,
  pages         TEXT,
  fetched_at    TIMESTAMPTZ DEFAULT now(),
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dbc_url ON douban_book_cache(douban_url);

ALTER TABLE douban_book_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dbc_read_all"   ON douban_book_cache FOR SELECT USING (true);
CREATE POLICY "dbc_insert_all" ON douban_book_cache FOR INSERT WITH CHECK (true);
CREATE POLICY "dbc_update_all" ON douban_book_cache FOR UPDATE USING (true);
CREATE POLICY "dbc_admin_write" ON douban_book_cache FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));
