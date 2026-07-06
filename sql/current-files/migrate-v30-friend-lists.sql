-- ============================================================
-- 以读攻独 · v30 迁移：好友列表
-- list_following / list_followers 返回关注/粉丝清单
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 我关注的
CREATE OR REPLACE FUNCTION public.list_following(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  city TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    COALESCE(ms.level, 0),
    COALESCE(ml.title, ''),
    p.city,
    uf.created_at
  FROM public.user_follows uf
  JOIN public.profiles p ON p.id = uf.following_id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE uf.follower_id = p_user_id
  ORDER BY uf.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 2. 关注我的
CREATE OR REPLACE FUNCTION public.list_followers(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  title TEXT,
  city TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    COALESCE(ms.level, 0),
    COALESCE(ml.title, ''),
    p.city,
    uf.created_at
  FROM public.user_follows uf
  JOIN public.profiles p ON p.id = uf.follower_id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE uf.following_id = p_user_id
  ORDER BY uf.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_following(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_followers(UUID) TO anon, authenticated;
