-- ============================================================
-- 以读攻独 · v35 迁移：书友搜索
-- 在「我的好友」页面按显示名字搜索书友，并进入公开个人主页。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.search_members_by_display_name(p_query TEXT)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  city TEXT,
  level INTEGER,
  title TEXT
) AS $$
DECLARE
  v_query TEXT;
BEGIN
  PERFORM public.require_authenticated_member();

  v_query := trim(COALESCE(p_query, ''));
  IF char_length(v_query) < 1 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    COALESCE(NULLIF(trim(p.display_name), ''), '书友') AS display_name,
    p.avatar_url,
    p.city,
    COALESCE(ms.level, 0) AS level,
    COALESCE(ml.title, '') AS title
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id <> auth.uid()
    AND COALESCE(p.display_name, '') ILIKE '%' || v_query || '%'
  ORDER BY
    CASE
      WHEN COALESCE(p.display_name, '') ILIKE v_query || '%' THEN 0
      ELSE 1
    END,
    COALESCE(ms.level, 0) DESC,
    COALESCE(p.display_name, '') ASC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.search_members_by_display_name(TEXT) TO authenticated;

COMMENT ON FUNCTION public.search_members_by_display_name(TEXT) IS
  '按显示名字搜索书友，用于个人中心-我的好友页面。';
