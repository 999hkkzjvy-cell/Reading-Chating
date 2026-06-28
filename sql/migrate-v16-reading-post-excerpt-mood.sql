-- ============================================================
-- 以读攻独 · v16 迁移：书友圈摘抄独立字段与阅读心情
-- 摘抄 excerpt 与感想/书评 content 分离；mood_color 控制卡片边框色
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS excerpt TEXT;

ALTER TABLE public.reading_posts
  ADD COLUMN IF NOT EXISTS mood_color TEXT;

ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_mood_color_valid;

ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_mood_color_valid
  CHECK (mood_color IS NULL OR mood_color ~ '^#[0-9A-Fa-f]{6}$');

CREATE OR REPLACE FUNCTION public.award_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_today_count INTEGER;
  v_delta INTEGER := 0;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_text_length INTEGER;
BEGIN
  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF NOT FOUND OR v_post.is_deleted OR v_post.visibility <> 'public' THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND is_active = true
  ) THEN
    RETURN;
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_count
  FROM public.contribution_logs
  WHERE user_id = v_post.user_id
    AND source_type = 'reading_post'
    AND reason = 'post_publish'
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_count >= 3 THEN
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_post.user_id, 'reading_post', p_post_id, 1, 'post_publish', 'reading_activity');
  v_delta := v_delta + 1;

  v_text_length := char_length(COALESCE(v_post.content, ''));
  IF v_text_length >= 50 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 2, 'post_long_content', 'reading_activity');
    v_delta := v_delta + 2;
  END IF;

  IF v_post.post_type = 'finished' THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 5, 'post_finished_book', 'reading_activity');
    v_delta := v_delta + 5;
  END IF;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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
  p_mood_color TEXT DEFAULT NULL
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

  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
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
    linked_book_id
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
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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
  updated_at TIMESTAMPTZ
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
    rp.updated_at
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

GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;
