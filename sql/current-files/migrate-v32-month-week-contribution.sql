-- ============================================================
-- 以读攻独 · v32 迁移：月贡献/周贡献跨周期自动重置
-- apply_member_contribution_delta 增加周期检测逻辑
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 从 contribution_logs 精确重算当月/当周贡献值
UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('month', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  contribution_week = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('week', timezone('Asia/Shanghai', now()))
    ), 0
  );

-- 2. 更新 apply_member_contribution_delta 增加周期重置
CREATE OR REPLACE FUNCTION public.apply_member_contribution_delta(
  p_user_id UUID,
  p_delta INTEGER
)
RETURNS VOID AS $$
DECLARE
  v_stats public.member_stats%ROWTYPE;
  v_this_month TIMESTAMPTZ;
  v_this_week TIMESTAMPTZ;
  v_last_month TIMESTAMPTZ;
  v_last_week TIMESTAMPTZ;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT * INTO v_stats FROM public.member_stats WHERE user_id = p_user_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_this_month := date_trunc('month', timezone('Asia/Shanghai', now()));
  v_this_week  := date_trunc('week', timezone('Asia/Shanghai', now()));
  v_last_month := date_trunc('month', v_stats.updated_at);
  v_last_week  := date_trunc('week', v_stats.updated_at);

  UPDATE public.member_stats
  SET
    contribution_total = GREATEST(contribution_total + p_delta, 0),
    contribution_month = GREATEST(
      CASE WHEN v_last_month < v_this_month THEN 0 ELSE contribution_month END + p_delta,
      0
    ),
    contribution_week = GREATEST(
      CASE WHEN v_last_week < v_this_week THEN 0 ELSE contribution_week END + p_delta,
      0
    ),
    updated_at = now()
  WHERE user_id = p_user_id;

  PERFORM public.recalculate_member_level(p_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
