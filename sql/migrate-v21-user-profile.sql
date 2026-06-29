-- ============================================================
-- 以读攻独 · v21 迁移：用户个人主页
-- get_public_member_profile：公开的会员信息
-- list_user_public_posts：某用户的公开书友圈
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 公开会员信息
CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
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

-- 2. 某用户的公开书友圈
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

GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_public_posts(UUID) TO anon, authenticated;
