-- ============================================================
-- 以读攻独 · 数据库迁移 v5 — 新书速递（豆瓣抓取 + 想共读投票）
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 新书缓存表
CREATE TABLE IF NOT EXISTS douban_new_books (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title           TEXT NOT NULL,
  cover_url       TEXT,
  author          TEXT,
  translator      TEXT,
  publisher       TEXT,
  description     TEXT,
  douban_url      TEXT NOT NULL,
  rating          TEXT,
  review_count    INTEGER DEFAULT 0,
  fiction_type    TEXT CHECK (fiction_type IN ('fiction','non-fiction')),
  scraped_at      TIMESTAMPTZ DEFAULT now(),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- 豆瓣链接作为去重键
ALTER TABLE douban_new_books ADD CONSTRAINT uq_douban_new_books_url UNIQUE (douban_url);

CREATE INDEX IF NOT EXISTS idx_dnb_scraped   ON douban_new_books(scraped_at);
CREATE INDEX IF NOT EXISTS idx_dnb_reviews   ON douban_new_books(review_count DESC);

ALTER TABLE douban_new_books ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "dnb_read_all" ON douban_new_books;
  CREATE POLICY "dnb_read_all" ON douban_new_books FOR SELECT USING (true);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "dnb_admin_write" ON douban_new_books;
  CREATE POLICY "dnb_admin_write" ON douban_new_books FOR ALL
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 2. 想共读投票表
CREATE TABLE IF NOT EXISTS reading_wishlist (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES douban_new_books(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_wishlist_book ON reading_wishlist(book_id);
CREATE INDEX IF NOT EXISTS idx_wishlist_user ON reading_wishlist(user_id);

ALTER TABLE reading_wishlist ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "wishlist_read_all" ON reading_wishlist;
  CREATE POLICY "wishlist_read_all" ON reading_wishlist FOR SELECT USING (true);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "wishlist_insert_auth" ON reading_wishlist;
  CREATE POLICY "wishlist_insert_auth" ON reading_wishlist FOR INSERT
    WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "wishlist_delete_own" ON reading_wishlist;
  CREATE POLICY "wishlist_delete_own" ON reading_wishlist FOR DELETE
    USING (auth.uid() = user_id);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
