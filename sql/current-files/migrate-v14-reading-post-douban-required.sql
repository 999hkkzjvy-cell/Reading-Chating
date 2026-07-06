-- ============================================================
-- 以读攻独 · v14 迁移：书友圈发布要求豆瓣链接与书名
-- 后端约束动态类型、可见范围、书名、豆瓣链接必填
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.reading_posts
  ALTER COLUMN douban_url SET NOT NULL;

ALTER TABLE public.reading_posts
  ALTER COLUMN book_title SET NOT NULL;

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = ''
    OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?'
  THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    content,
    visibility,
    linked_book_id
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    p_visibility,
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
