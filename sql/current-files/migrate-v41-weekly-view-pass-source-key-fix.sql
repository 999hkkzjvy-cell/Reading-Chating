-- ============================================================
-- 以读攻独 · v41 迁移：修复每周资源浏览券发放 source_key 歧义
-- admin_issue_weekly_view_passes 的 RETURNS TABLE 含 source_key 输出列，
-- 与 view_passes.source_key 字段同名，导致 ON CONFLICT 谓词中
-- column reference "source_key" is ambiguous。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
#variable_conflict use_column
DECLARE
  v_source_key TEXT;
  v_inserted_passes INTEGER;
  v_inserted_users INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  v_source_key := 'weekly_' || to_char(date_trunc('week', now()), 'IYYY_IW');

  WITH weekly_activity AS (
    SELECT
      cl.user_id,
      SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= date_trunc('week', now())
      AND cl.created_at < date_trunc('week', now()) + interval '7 days'
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      ml.weekly_view_passes,
      COALESCE(wa.points, 0) AS weekly_activity_points,
      row_number() OVER (
        ORDER BY COALESCE(wa.points, 0) DESC, ms.contribution_total DESC, ms.user_id
      ) AS rank_position
    FROM public.member_stats ms
    JOIN public.member_levels ml ON ml.level = ms.level
    LEFT JOIN weekly_activity wa ON wa.user_id = ms.user_id
    WHERE ml.weekly_view_passes > 0
  ),
  expanded AS (
    SELECT
      r.user_id,
      generate_series(
        1,
        r.weekly_view_passes * CASE
          WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2
          ELSE 1
        END
      ) AS pass_no
    FROM ranked r
  ),
  passes_to_insert AS (
    SELECT
      e.user_id,
      (v_source_key || '_' || e.user_id || '_' || e.pass_no) AS pass_source_key
    FROM expanded e
  ),
  inserted AS (
    INSERT INTO public.view_passes
      (user_id, status, issued_reason, source_key, issued_at, expires_at)
    SELECT
      pti.user_id,
      'available',
      'weekly',
      pti.pass_source_key,
      now(),
      now() + interval '7 days'
    FROM passes_to_insert pti
    ON CONFLICT (user_id, source_key) WHERE (source_key IS NOT NULL)
    DO NOTHING
    RETURNING public.view_passes.user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT inserted.user_id)::INTEGER
    INTO v_inserted_passes, v_inserted_users
  FROM inserted;

  issued_passes := COALESCE(v_inserted_passes, 0);
  issued_users := COALESCE(v_inserted_users, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;
