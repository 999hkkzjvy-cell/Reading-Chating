-- ============================================================
-- 以读攻独 · v11 迁移：修正会员等级重算补发逻辑
-- 让 recalculate_member_level 在重算时补齐当前等级应有徽章
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key
    INTO v_new_level, v_new_tier, v_new_badge_key
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 等级徽章是历史成就：重算时补齐当前等级及以下所有应有徽章。
  -- 这样即使管理员手动改过 level，或之前发放中断，再重算也能修复缺失徽章。
  INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
  SELECT p_user_id, ml.badge_key, 'level', 'level_recalculate'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.badge_key IS NOT NULL
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  -- 共读兑换券仍按等级奖励每级最多一张。这里补齐缺失记录，
  -- 已使用或已回收的同等级券不会重复创建。
  INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
  SELECT p_user_id, 'available', ml.level, 'level_up'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.reward_redemption_tickets > 0
  ON CONFLICT DO NOTHING;

  IF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.recalculate_member_level(UUID) IS
  '根据贡献值重算会员等级，补齐当前等级应有徽章和缺失的等级奖励券';
