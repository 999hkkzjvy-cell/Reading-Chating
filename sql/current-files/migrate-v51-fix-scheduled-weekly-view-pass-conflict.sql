-- ============================================================
-- 以读攻独 · v51 迁移：修复定时资源浏览券发放的 source_key 歧义
--
-- v50 的私有函数 RETURNS TABLE 含 source_key 输出变量，和
-- view_passes.source_key 在 ON CONFLICT 谓词中同名，导致 Cron 执行失败。
-- ============================================================

CREATE OR REPLACE FUNCTION private.issue_weekly_view_passes(
  p_period_start TIMESTAMPTZ,
  p_issued_at TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
#variable_conflict use_column
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
    SELECT cl.user_id, SUM(cl.points)::INTEGER AS points
    FROM public.contribution_logs AS cl
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
    FROM public.member_stats AS ms
    JOIN public.member_levels AS ml ON ml.level = ms.level
    LEFT JOIN weekly_activity AS wa ON wa.user_id = ms.user_id
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
    FROM ranked AS r
  ),
  inserted AS (
    INSERT INTO public.view_passes (
      user_id, status, issued_reason, source_key, issued_at, expires_at
    )
    SELECT
      e.user_id,
      'available',
      'weekly',
      v_source_key || '_' || e.user_id || '_' || e.pass_no,
      p_issued_at,
      p_issued_at + interval '7 days'
    FROM expanded AS e
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
