-- ============================================================
-- 以读攻独 · v33 迁移：书友圈仅登录会员可浏览
-- 游客不可浏览书友圈广场、贡献榜、个人主页中的书友圈动态
-- 在 Supabase SQL Editor 中执行
-- ============================================================

DROP POLICY IF EXISTS "reading_posts_read_public_self_or_admin" ON public.reading_posts;
CREATE POLICY "reading_posts_read_public_self_or_admin"
  ON public.reading_posts
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND (
      (visibility = 'public' AND is_deleted = false)
      OR auth.uid() = user_id
      OR public.is_admin()
    )
  );

CREATE OR REPLACE FUNCTION public.require_authenticated_member()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login_required';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope = 'friends' AND (
        (rp.visibility = 'public' OR rp.visibility = 'friends')
        AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = rp.user_id)
      ))
      OR (p_scope = 'public' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.search_reading_posts(p_query TEXT)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND rp.visibility = 'public'
    AND (
      rp.book_title ILIKE '%' || p_query || '%'
      OR rp.author ILIKE '%' || p_query || '%'
    )
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_user_public_posts(p_user_id UUID)
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
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友'),
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
    ),
    COALESCE(ms.level, 0),
    COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.user_id = p_user_id
    AND rp.is_deleted = false
    AND rp.visibility = 'public'
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  city TEXT,
  wechat_id TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    p.bio,
    p.city,
    p.wechat_id,
    COALESCE(ms.level, 0),
    COALESCE(ms.tier, '基础会员'),
    COALESCE(ml.title, ''),
    COALESCE(ms.contribution_total, 0),
    COALESCE(ms.contribution_month, 0),
    COALESCE(ms.contribution_week, 0),
    ms.current_badge_key
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_contribution_leaderboard(p_type TEXT DEFAULT 'total')
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  contribution INTEGER
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY
        CASE p_type
          WHEN 'total' THEN ms.contribution_total
          WHEN 'month' THEN ms.contribution_month
          WHEN 'week'  THEN ms.contribution_week
        END DESC,
        p.created_at ASC
    )::BIGINT AS rank,
    ms.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    COALESCE(ms.level, 0) AS level,
    COALESCE(ml.title, '') AS title,
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END AS contribution
  FROM public.member_stats ms
  JOIN public.profiles p ON p.id = ms.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END > 0
  ORDER BY
    CASE p_type
      WHEN 'total' THEN ms.contribution_total
      WHEN 'month' THEN ms.contribution_month
      WHEN 'week'  THEN ms.contribution_week
    END DESC,
    p.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.list_reading_posts(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.search_reading_posts(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_user_public_posts(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_public_member_profile(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) FROM anon;

GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_reading_posts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_public_posts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO authenticated;

COMMENT ON FUNCTION public.require_authenticated_member() IS '要求当前请求来自已登录用户，用于限制书友圈浏览';
