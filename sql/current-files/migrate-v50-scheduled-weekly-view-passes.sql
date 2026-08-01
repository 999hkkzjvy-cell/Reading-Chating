-- ============================================================
-- 以读攻独 · v50 迁移：每周资源浏览券定时核算与发放
--
-- 每周日 20:00（Asia/Shanghai / UTC+8）自动核算当周阅读贡献，
-- 按会员等级发放浏览券，前 5 名活跃会员翻倍；同一结算周可重复执行
-- 但不会重复插入。Supabase 数据库默认使用 UTC，因此 Cron 为周日 12:00 UTC。
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;

CREATE OR REPLACE FUNCTION private.issue_weekly_view_passes(
  p_period_start TIMESTAMPTZ,
  p_issued_at TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_period_start TIMESTAMPTZ := p_period_start;
  v_period_end TIMESTAMPTZ := p_period_start + interval '7 days';
  v_source_key TEXT;
  v_inserted_passes INTEGER;
  v_inserted_users INTEGER;
BEGIN
  IF v_period_start <> (date_trunc('week', timezone('Asia/Shanghai', v_period_start)) AT TIME ZONE 'Asia/Shanghai') THEN
    RAISE EXCEPTION 'p_period_start must be the beginning of an Asia/Shanghai week';
  END IF;

  v_source_key := 'weekly_' || to_char(v_period_start AT TIME ZONE 'Asia/Shanghai', 'IYYY_IW');

  WITH weekly_activity AS (
    SELECT
      cl.user_id,
      SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs cl
    WHERE cl.is_active = true
      AND cl.contribution_scope = 'reading_activity'
      AND cl.created_at >= v_period_start
      AND cl.created_at < v_period_end
    GROUP BY cl.user_id
  ),
  ranked AS (
    SELECT
      ms.user_id,
      ml.weekly_view_passes,
      COALESCE(wa.points, 0) AS weekly_activity_points,
      ROW_NUMBER() OVER (
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
      GENERATE_SERIES(
        1,
        r.weekly_view_passes * CASE
          WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2
          ELSE 1
        END
      ) AS pass_no
    FROM ranked r
  ),
  inserted AS (
    INSERT INTO public.view_passes (
      user_id,
      status,
      issued_reason,
      source_key,
      issued_at,
      expires_at
    )
    SELECT
      e.user_id,
      'available',
      'weekly',
      v_source_key || '_' || e.user_id || '_' || e.pass_no,
      p_issued_at,
      p_issued_at + interval '7 days'
    FROM expanded e
    ON CONFLICT (user_id, source_key) WHERE (source_key IS NOT NULL)
    DO NOTHING
    RETURNING user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT user_id)::INTEGER
    INTO v_inserted_passes, v_inserted_users
  FROM inserted;

  issued_users := COALESCE(v_inserted_users, 0);
  issued_passes := COALESCE(v_inserted_passes, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION private.issue_weekly_view_passes(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_scheduled_weekly_view_passes()
RETURNS VOID AS $$
DECLARE
  v_period_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
BEGIN
  PERFORM private.issue_weekly_view_passes(v_period_start, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION private.run_scheduled_weekly_view_passes() FROM PUBLIC, anon, authenticated;

-- 保留受管理员权限保护的 RPC 作为故障排查/补发兜底；前台不再提供手动入口。
CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_period_start TIMESTAMPTZ := date_trunc('week', timezone('Asia/Shanghai', now())) AT TIME ZONE 'Asia/Shanghai';
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  RETURN QUERY
  SELECT * FROM private.issue_weekly_view_passes(v_period_start, now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;

DO $schedule$
DECLARE
  v_job_id BIGINT;
BEGIN
  FOR v_job_id IN
    SELECT jobid
    FROM cron.job
    WHERE jobname = 'weekly-view-passes-sunday-2000-shanghai'
  LOOP
    PERFORM cron.unschedule(v_job_id);
  END LOOP;

  PERFORM cron.schedule(
    'weekly-view-passes-sunday-2000-shanghai',
    '0 12 * * 0',
    'SELECT private.run_scheduled_weekly_view_passes();'
  );
END;
$schedule$;

COMMENT ON FUNCTION private.issue_weekly_view_passes(TIMESTAMPTZ, TIMESTAMPTZ) IS
  '按指定上海自然周核算阅读贡献并发放浏览券；source_key 保证同一周重复执行不重复发券。';

COMMENT ON FUNCTION private.run_scheduled_weekly_view_passes() IS
  '由 pg_cron 于每周日 12:00 UTC（北京时间 20:00）调用。';
