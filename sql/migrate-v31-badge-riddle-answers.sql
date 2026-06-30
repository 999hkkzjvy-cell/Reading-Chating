-- ============================================================
-- 以读攻独 · v31 迁移：徽章成就谜面答题
-- 每枚徽章答对一次后记录状态，并奖励 10 贡献值
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.badge_riddle_answers (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key       TEXT NOT NULL REFERENCES public.badge_catalog(badge_key) ON DELETE CASCADE,
  answer_text     TEXT NOT NULL,
  awarded_points  INTEGER NOT NULL DEFAULT 10,
  solved_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, badge_key)
);

CREATE INDEX IF NOT EXISTS idx_badge_riddle_answers_user
  ON public.badge_riddle_answers(user_id, solved_at DESC);

ALTER TABLE public.badge_riddle_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badge_riddle_answers_read_self_or_admin" ON public.badge_riddle_answers;
CREATE POLICY "badge_riddle_answers_read_self_or_admin"
  ON public.badge_riddle_answers
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "badge_riddle_answers_admin_write" ON public.badge_riddle_answers;
CREATE POLICY "badge_riddle_answers_admin_write"
  ON public.badge_riddle_answers
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.badge_riddle_answer_tokens(p_badge_key TEXT)
RETURNS TEXT[] AS $$
BEGIN
  RETURN CASE p_badge_key
    WHEN 'founder' THEN ARRAY['文学爆炸', '四主将', '爆炸']
    WHEN 'level_01_wanderer' THEN ARRAY['聂鲁达', '巴勃罗', '元素颂歌', '漫歌', '黑岛']
    WHEN 'level_02_adventurer' THEN ARRAY['塞万提斯', '堂吉诃德']
    WHEN 'level_03_chronicler' THEN ARRAY['加西拉索', '印卡王室述评', '印卡王室评述']
    WHEN 'level_04_seeker' THEN ARRAY['波拉尼奥', '荒野侦探', '2666']
    WHEN 'level_05_tunnel' THEN ARRAY['萨瓦托', '亚巴顿']
    WHEN 'level_06_labyrinth' THEN ARRAY['博尔赫斯', '阿莱夫', '虚构集', '小径分岔']
    WHEN 'level_07_wallbreaker' THEN ARRAY['胡安娜', '克鲁兹', '索尔胡安娜']
    WHEN 'level_08_player' THEN ARRAY['科塔萨尔', '跳房子']
    WHEN 'level_09_wordtamer' THEN ARRAY['因凡特', '三只忧伤的老虎', '忧伤的老虎']
    WHEN 'level_10_stargazer' THEN ARRAY['李斯佩克朵', '李斯佩克多', '星辰时刻']
    WHEN 'level_11_architect' THEN ARRAY['卡彭铁尔', '人间王国', '千柱之城']
    WHEN 'level_12_nether' THEN ARRAY['鲁尔福', '佩德罗巴拉莫', '燃烧的原野']
    WHEN 'level_13_wasteport' THEN ARRAY['奥内蒂', '造船厂', '收尸人']
    WHEN 'level_14_alchemist' THEN ARRAY['马尔克斯', '百年孤独']
    WHEN 'level_15_maskman' THEN ARRAY['富恩特斯', '奥拉', '阿尔特米奥', '最明净的地区']
    WHEN 'level_16_godslayer' THEN ARRAY['略萨', '巴尔加斯', '城市与狗', '酒吧长谈', '公羊的节日']
    ELSE ARRAY[]::TEXT[]
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.normalize_badge_riddle_answer(p_answer TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN lower(
    regexp_replace(
      COALESCE(p_answer, ''),
      '[[:space:][:punct:]，。、《》「」『』（）【】·—-]+',
      '',
      'g'
    )
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

CREATE OR REPLACE FUNCTION public.submit_badge_riddle_answer(
  p_badge_key TEXT,
  p_answer TEXT
)
RETURNS TABLE (
  correct BOOLEAN,
  already_solved BOOLEAN,
  awarded_points INTEGER,
  message TEXT
) AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_answer TEXT := public.normalize_badge_riddle_answer(p_answer);
  v_tokens TEXT[];
  v_correct BOOLEAN := false;
  v_answer_id BIGINT;
  v_points INTEGER := 10;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF COALESCE(trim(p_badge_key), '') = '' THEN
    RAISE EXCEPTION 'badge_key_required';
  END IF;

  IF COALESCE(v_answer, '') = '' THEN
    RETURN QUERY SELECT false, false, 0, '请先输入答案。';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.user_badges
    WHERE user_id = v_user_id
      AND badge_key = p_badge_key
      AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'badge_not_owned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.badge_riddle_answers
    WHERE user_id = v_user_id
      AND badge_key = p_badge_key
  ) THEN
    RETURN QUERY SELECT true, true, 0, '这枚徽章已经答对过了。';
    RETURN;
  END IF;

  v_tokens := public.badge_riddle_answer_tokens(p_badge_key);

  IF COALESCE(array_length(v_tokens, 1), 0) = 0 THEN
    RAISE EXCEPTION 'badge_riddle_not_configured';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM unnest(v_tokens) AS token
    WHERE position(public.normalize_badge_riddle_answer(token) IN v_answer) > 0
  ) INTO v_correct;

  IF NOT v_correct THEN
    RETURN QUERY SELECT false, false, 0, '答案还不对，可以再试一次。';
    RETURN;
  END IF;

  INSERT INTO public.badge_riddle_answers
    (user_id, badge_key, answer_text, awarded_points)
  VALUES
    (v_user_id, p_badge_key, left(p_answer, 200), v_points)
  ON CONFLICT (user_id, badge_key) DO NOTHING
  RETURNING id INTO v_answer_id;

  IF v_answer_id IS NULL THEN
    RETURN QUERY SELECT true, true, 0, '这枚徽章已经答对过了。';
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_user_id, 'badge_riddle', v_answer_id, v_points, 'badge_riddle_solved', 'system_reward');

  PERFORM public.apply_member_contribution_delta(v_user_id, v_points);

  RETURN QUERY SELECT true, false, v_points, '答对了，已增加 10 贡献值。';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.submit_badge_riddle_answer(TEXT, TEXT) TO authenticated;

COMMENT ON TABLE public.badge_riddle_answers IS '徽章成就谜面答题记录：每个用户每枚徽章只可领取一次贡献值奖励';
COMMENT ON FUNCTION public.submit_badge_riddle_answer(TEXT, TEXT) IS '提交徽章谜面答案；答对一次奖励 10 贡献值，答错不扣分';
