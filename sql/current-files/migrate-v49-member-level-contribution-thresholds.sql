-- ============================================================
-- 以读攻独 · v49 迁移：会员等级贡献值门槛调整
-- 白银会员及后续等级采用新的贡献值区间，并重算所有现有会员等级。
-- 在 Supabase SQL Editor 中执行。
-- ============================================================

UPDATE public.member_levels
SET min_contribution = CASE level
      WHEN 7 THEN 701
      WHEN 8 THEN 1101
      WHEN 9 THEN 1501
      WHEN 10 THEN 2001
      WHEN 11 THEN 2501
      WHEN 12 THEN 3001
      WHEN 13 THEN 4001
      WHEN 14 THEN 5001
      WHEN 15 THEN 7001
      WHEN 16 THEN 10001
    END,
    max_contribution = CASE level
      WHEN 7 THEN 1100
      WHEN 8 THEN 1500
      WHEN 9 THEN 2000
      WHEN 10 THEN 2500
      WHEN 11 THEN 3000
      WHEN 12 THEN 4000
      WHEN 13 THEN 5000
      WHEN 14 THEN 7000
      WHEN 15 THEN 10000
      WHEN 16 THEN NULL
    END,
    updated_at = now()
WHERE level BETWEEN 7 AND 16;

-- 同步已有会员的等级、当前成长徽章与未使用的等级兑换券。
-- 当前版本的重算函数只在真实升级时发送通知；本次门槛上调不会产生升级通知。
DO $$
DECLARE
  v_user_id UUID;
BEGIN
  FOR v_user_id IN SELECT user_id FROM public.member_stats
  LOOP
    PERFORM public.recalculate_member_level(v_user_id);
  END LOOP;
END;
$$;

COMMENT ON TABLE public.member_levels IS
  '会员等级配置：Lv.0-Lv.16、段位、贡献值区间和每周资源浏览券数量；v49 起白银会员为 701-3000，黄金会员为 3001 及以上。';
