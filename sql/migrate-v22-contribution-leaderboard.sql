-- ============================================================
-- 以读攻独 · v22 迁移：贡献榜单
-- 总榜 / 月榜 / 周榜，各取前10名，同分按注册时间先后排序
-- 在 Supabase SQL Editor 中执行
-- ============================================================

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

GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO anon, authenticated;
