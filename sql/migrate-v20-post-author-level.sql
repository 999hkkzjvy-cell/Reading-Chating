-- ============================================================
-- 以读攻独 · v20 迁移：书友圈动态卡片展示用户等级
-- list_reading_posts 追加 member_level 和 member_title 字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

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
  rating NUMERIC,
  has_liked BOOLEAN,
  member_level INTEGER,
  member_title TEXT
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
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ) AS has_liked,
    COALESCE(ms.level, 0) AS member_level,
    COALESCE(ml.title, '') AS member_title
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = ms.level
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;
