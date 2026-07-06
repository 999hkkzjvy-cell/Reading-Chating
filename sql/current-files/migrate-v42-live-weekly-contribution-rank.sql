-- ============================================================
-- 以读攻独 · v42 迁移：周贡献榜实时按当前自然周计算
--
-- 背景：
-- member_stats.contribution_week 是缓存字段。旧逻辑只在用户产生新贡献时重置，
-- 所以上周有分、本周没有动作的用户可能继续残留在本周榜。
--
-- 本迁移：
-- 1. 将 get_contribution_leaderboard('week') 改为实时汇总当前上海自然周的 reading_activity 日志。
-- 2. 将 get_my_weekly_contribution_rank() 改为实时汇总当前上海自然周的 reading_activity 日志。
-- 3. 顺手校准 member_stats.contribution_week，清掉当前缓存里的旧周残留。
-- ============================================================

UPDATE public.member_stats ms
SET
  contribution_week = COALESCE(
    (
      SELECT SUM(cl.points)
      FROM public.contribution_logs cl
      WHERE cl.user_id = ms.user_id
        AND cl.is_active = true
        AND cl.contribution_scope = 'reading_activity'
        AND cl.created_at >= (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai')
        AND cl.created_at <  (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days'
    ),
    0
  ),
  updated_at = now();

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
DECLARE
  v_week_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end   TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  WITH live_week AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_week_start
      AND cl.created_at < v_week_end
    GROUP BY cl.user_id
  ),
  scored AS (
    SELECT
      ms.user_id,
      COALESCE(p.display_name, '书友') AS display_name,
      p.avatar_url,
      COALESCE(ms.level, 0) AS level,
      COALESCE(ml.title, '') AS title,
      p.created_at,
      CASE p_type
        WHEN 'total' THEN ms.contribution_total
        WHEN 'month' THEN ms.contribution_month
        WHEN 'week'  THEN COALESCE(lw.contribution, 0)
      END::INTEGER AS contribution
    FROM public.member_stats ms
    JOIN public.profiles p ON p.id = ms.user_id
    LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
    LEFT JOIN live_week lw ON lw.user_id = ms.user_id
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY scored.contribution DESC, scored.created_at ASC)::BIGINT AS rank,
    scored.user_id,
    scored.display_name,
    scored.avatar_url,
    scored.level,
    scored.title,
    scored.contribution
  FROM scored
  WHERE scored.contribution > 0
  ORDER BY scored.contribution DESC, scored.created_at ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_contribution_leaderboard(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_weekly_contribution_rank()
RETURNS TABLE (
  rank_position INTEGER,
  total_members INTEGER,
  contribution_week INTEGER
) AS $$
DECLARE
  v_week_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end   TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  RETURN QUERY
  WITH live_week AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution_week
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_week_start
      AND cl.created_at < v_week_end
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      COALESCE(lw.contribution_week, 0)::INTEGER AS contribution_week,
      RANK() OVER (ORDER BY COALESCE(lw.contribution_week, 0) DESC) AS rank_position,
      COUNT(*) OVER () AS total_members
    FROM public.member_stats ms
    LEFT JOIN live_week lw ON lw.user_id = ms.user_id
  )
  SELECT
    ranked.rank_position::INTEGER,
    ranked.total_members::INTEGER,
    ranked.contribution_week::INTEGER
  FROM ranked
  WHERE ranked.user_id = auth.uid();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() TO authenticated;

COMMENT ON FUNCTION public.get_contribution_leaderboard(TEXT) IS
  '贡献榜单。week 类型实时汇总当前上海自然周 reading_activity 贡献，避免 member_stats 周缓存残留旧数据。';

COMMENT ON FUNCTION public.get_my_weekly_contribution_rank() IS
  '返回当前登录用户在当前上海自然周 reading_activity 贡献中的实时排名。';
