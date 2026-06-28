-- ============================================================
-- 以读攻独 · v12 迁移：当前用户本周贡献排名
-- 为会员中心“本周贡献值”卡片提供当前周排名
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_my_weekly_contribution_rank()
RETURNS TABLE (
  rank_position INTEGER,
  total_members INTEGER,
  contribution_week INTEGER
) AS $$
  WITH ranked AS (
    SELECT
      ms.user_id,
      ms.contribution_week,
      RANK() OVER (ORDER BY ms.contribution_week DESC) AS rank_position,
      COUNT(*) OVER () AS total_members
    FROM public.member_stats ms
  )
  SELECT
    ranked.rank_position::INTEGER,
    ranked.total_members::INTEGER,
    ranked.contribution_week::INTEGER
  FROM ranked
  WHERE ranked.user_id = auth.uid();
$$ LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_my_weekly_contribution_rank() TO authenticated;

COMMENT ON FUNCTION public.get_my_weekly_contribution_rank() IS
  '返回当前登录用户在 member_stats.contribution_week 中的本周贡献排名';
