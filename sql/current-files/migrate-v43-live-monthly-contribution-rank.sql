-- ============================================================
-- 以读攻独 · v43 迁移：月贡献榜实时按当前自然月计算
--
-- 背景：
-- member_stats.contribution_month 也是缓存字段。旧逻辑只在用户产生新贡献时重置，
-- 所以上月有分、本月没有动作的用户可能继续残留在月贡献榜。
--
-- 本迁移：
-- 1. 将 get_contribution_leaderboard('month') 改为实时汇总当前上海自然月的 reading_activity 日志。
-- 2. 保留 v42 中 get_contribution_leaderboard('week') 的实时当前上海自然周口径。
-- 3. 顺手校准 member_stats.contribution_month，清掉当前缓存里的旧月残留。
-- ============================================================

UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (
      SELECT SUM(cl.points)
      FROM public.contribution_logs cl
      WHERE cl.user_id = ms.user_id
        AND cl.is_active = true
        AND cl.contribution_scope = 'reading_activity'
        AND cl.created_at >= (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai')
        AND cl.created_at <  (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '1 month'
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
  v_month_start TIMESTAMPTZ := date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_month_end   TIMESTAMPTZ := (date_trunc('month', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '1 month';
  v_week_start  TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
  v_week_end    TIMESTAMPTZ := (date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai') + interval '7 days';
BEGIN
  IF p_type NOT IN ('total', 'month', 'week') THEN
    RAISE EXCEPTION 'Invalid leaderboard type';
  END IF;

  RETURN QUERY
  WITH live_month AS (
    SELECT
      cl.user_id,
      COALESCE(SUM(cl.points), 0)::INTEGER AS contribution
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_month_start
      AND cl.created_at < v_month_end
    GROUP BY cl.user_id
  ),
  live_week AS (
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
        WHEN 'month' THEN COALESCE(lm.contribution, 0)
        WHEN 'week'  THEN COALESCE(lw.contribution, 0)
      END::INTEGER AS contribution
    FROM public.member_stats ms
    JOIN public.profiles p ON p.id = ms.user_id
    LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
    LEFT JOIN live_month lm ON lm.user_id = ms.user_id
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

COMMENT ON FUNCTION public.get_contribution_leaderboard(TEXT) IS
  '贡献榜单。month/week 类型实时汇总当前上海自然月/自然周 reading_activity 贡献，避免 member_stats 月周缓存残留旧数据。';
