-- ============================================================
-- 以读攻独 · v17 迁移：书友圈动态类型精简 + 已读评分
-- 动态类型限制为 想读/在读/已读 三种；已读时可填写 -10~10 评分
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 添加评分列（-10 ~ 10，最多2位小数）
ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS rating NUMERIC(4,2);

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_rating_range;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_rating_range
  CHECK (rating IS NULL OR (rating >= -10 AND rating <= 10));

-- 2. 更新 post_type 约束为三种
-- 注意：如果表中已存在旧类型（excerpt/reflection/review）的记录，需要先处理
-- 可选：将旧类型记录迁移到兼容类型，或删除旧记录
-- UPDATE public.reading_posts SET post_type = 'finished' WHERE post_type IN ('excerpt', 'reflection', 'review');

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_post_type_check;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_post_type_check
  CHECK (post_type IN ('want', 'reading', 'finished'));

-- 3. 更新 create_reading_post 函数：新增 p_rating 参数，精简 post_type 校验
DROP FUNCTION IF EXISTS public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
  v_mood_color TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
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

  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
  END IF;

  -- 评分仅已读类型可填，校验范围 -10~10，最多2位小数
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    excerpt,
    content,
    mood_color,
    visibility,
    linked_book_id,
    rating
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_excerpt, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    v_mood_color,
    p_visibility,
    p_linked_book_id,
    p_rating
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. 更新 list_reading_posts 函数：返回 rating 字段
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 授权
GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

COMMENT ON TABLE public.reading_posts IS '书友圈阅读动态：想读、在读、已读（附评分）';
