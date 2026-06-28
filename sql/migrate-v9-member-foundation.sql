-- ============================================================
-- 以读攻独 · v9 迁移：会员系统第一阶段
-- 数据库基础、等级配置、徽章 catalog、注册初始化与首次资源浏览券
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- ------------------------------------------------------------
-- 0. 通用管理员判断函数
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ------------------------------------------------------------
-- 1. 会员等级配置
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_levels (
  level                       INTEGER PRIMARY KEY,
  title                       TEXT,
  tier                        TEXT NOT NULL,
  min_contribution            INTEGER NOT NULL,
  max_contribution            INTEGER,
  weekly_view_passes          INTEGER NOT NULL DEFAULT 0,
  badge_key                   TEXT,
  reward_redemption_tickets   INTEGER NOT NULL DEFAULT 0,
  is_active                   BOOLEAN NOT NULL DEFAULT true,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT member_levels_level_nonnegative CHECK (level >= 0),
  CONSTRAINT member_levels_min_nonnegative CHECK (min_contribution >= 0),
  CONSTRAINT member_levels_max_valid CHECK (max_contribution IS NULL OR max_contribution >= min_contribution),
  CONSTRAINT member_levels_weekly_passes_nonnegative CHECK (weekly_view_passes >= 0),
  CONSTRAINT member_levels_reward_tickets_nonnegative CHECK (reward_redemption_tickets >= 0)
);

ALTER TABLE public.member_levels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "member_levels_read_all" ON public.member_levels;
CREATE POLICY "member_levels_read_all" ON public.member_levels FOR SELECT USING (true);
DROP POLICY IF EXISTS "member_levels_admin_write" ON public.member_levels;
CREATE POLICY "member_levels_admin_write" ON public.member_levels FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

INSERT INTO public.member_levels
  (level, title, tier, min_contribution, max_contribution, weekly_view_passes, badge_key, reward_redemption_tickets)
VALUES
  (0,  NULL,       '基础会员', 0,    5,    0, NULL,                  0),
  (1,  '漫游者',   '青铜会员', 6,    30,   1, 'level_01_wanderer',    1),
  (2,  '冒险者',   '青铜会员', 31,   100,  1, 'level_02_adventurer',  1),
  (3,  '纪事者',   '青铜会员', 101,  200,  1, 'level_03_chronicler',  1),
  (4,  '追寻者',   '青铜会员', 201,  320,  1, 'level_04_seeker',      1),
  (5,  '隧行者',   '青铜会员', 321,  500,  1, 'level_05_tunnel',      1),
  (6,  '迷宫客',   '青铜会员', 501,  700,  1, 'level_06_labyrinth',   1),
  (7,  '破壁者',   '白银会员', 701,  950,  2, 'level_07_wallbreaker', 1),
  (8,  '游戏者',   '白银会员', 951,  1200, 2, 'level_08_player',      1),
  (9,  '驭词者',   '白银会员', 1201, 1500, 2, 'level_09_wordtamer',   1),
  (10, '观星者',   '白银会员', 1501, 1800, 2, 'level_10_stargazer',   1),
  (11, '建筑师',   '白银会员', 1801, 2150, 2, 'level_11_architect',   1),
  (12, '冥语者',   '黄金会员', 2151, 2500, 3, 'level_12_nether',      1),
  (13, '荒港客',   '黄金会员', 2501, 2900, 3, 'level_13_wasteport',   1),
  (14, '炼金士',   '黄金会员', 2901, 3300, 3, 'level_14_alchemist',   1),
  (15, '面具人',   '黄金会员', 3301, 4000, 3, 'level_15_maskman',     1),
  (16, '弑神者',   '黄金会员', 4001, NULL, 3, 'level_16_godslayer',   1)
ON CONFLICT (level) DO UPDATE SET
  title = EXCLUDED.title,
  tier = EXCLUDED.tier,
  min_contribution = EXCLUDED.min_contribution,
  max_contribution = EXCLUDED.max_contribution,
  weekly_view_passes = EXCLUDED.weekly_view_passes,
  badge_key = EXCLUDED.badge_key,
  reward_redemption_tickets = EXCLUDED.reward_redemption_tickets,
  is_active = true,
  updated_at = now();

-- ------------------------------------------------------------
-- 2. 徽章 catalog 与 Supabase Storage bucket
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('badges', 'badges', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "badges_read_all" ON storage.objects;
CREATE POLICY "badges_read_all" ON storage.objects FOR SELECT
  USING (bucket_id = 'badges');

DROP POLICY IF EXISTS "badges_admin_insert" ON storage.objects;
CREATE POLICY "badges_admin_insert" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'badges' AND public.is_admin());

DROP POLICY IF EXISTS "badges_admin_update" ON storage.objects;
CREATE POLICY "badges_admin_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'badges' AND public.is_admin())
  WITH CHECK (bucket_id = 'badges' AND public.is_admin());

DROP POLICY IF EXISTS "badges_admin_delete" ON storage.objects;
CREATE POLICY "badges_admin_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'badges' AND public.is_admin());

CREATE TABLE IF NOT EXISTS public.badge_catalog (
  badge_key     TEXT PRIMARY KEY,
  badge_type    TEXT NOT NULL CHECK (badge_type IN ('level', 'founder', 'commemorative', 'behavior')),
  title         TEXT NOT NULL,
  level         INTEGER,
  image_bucket  TEXT NOT NULL DEFAULT 'badges',
  image_path    TEXT,
  riddle_key    TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT badge_catalog_level_for_level_badges CHECK (
    (badge_type = 'level' AND level IS NOT NULL) OR
    (badge_type <> 'level')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_badge_catalog_level_unique
  ON public.badge_catalog(level)
  WHERE badge_type = 'level' AND level IS NOT NULL;

ALTER TABLE public.badge_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "badge_catalog_read_all" ON public.badge_catalog;
CREATE POLICY "badge_catalog_read_all" ON public.badge_catalog FOR SELECT USING (true);
DROP POLICY IF EXISTS "badge_catalog_admin_write" ON public.badge_catalog;
CREATE POLICY "badge_catalog_admin_write" ON public.badge_catalog FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

INSERT INTO public.badge_catalog
  (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
VALUES
  ('level_01_wanderer',    'level',   '漫游者', 1,  'badges', 'final/lv01-wanderer.png',         'level_01_wanderer'),
  ('level_02_adventurer',  'level',   '冒险者', 2,  'badges', 'final/lv02-adventurer.png',       'level_02_adventurer'),
  ('level_03_chronicler',  'level',   '纪事者', 3,  'badges', 'final/lv03-chronicler.png',       'level_03_chronicler'),
  ('level_04_seeker',      'level',   '追寻者', 4,  'badges', 'final/lv04-seeker.png',           'level_04_seeker'),
  ('level_05_tunnel',      'level',   '隧行者', 5,  'badges', 'final/lv05-tunnel-walker.png',    'level_05_tunnel'),
  ('level_06_labyrinth',   'level',   '迷宫客', 6,  'badges', 'final/lv06-labyrinth-guest.png',  'level_06_labyrinth'),
  ('level_07_wallbreaker', 'level',   '破壁者', 7,  'badges', 'final/lv07-wallbreaker.png',      'level_07_wallbreaker'),
  ('level_08_player',      'level',   '游戏者', 8,  'badges', 'final/lv08-player.png',           'level_08_player'),
  ('level_09_wordtamer',   'level',   '驭词者', 9,  'badges', 'final/lv09-wordtamer.png',        'level_09_wordtamer'),
  ('level_10_stargazer',   'level',   '观星者', 10, 'badges', 'final/lv10-stargazer.png',        'level_10_stargazer'),
  ('level_11_architect',   'level',   '建筑师', 11, 'badges', 'final/lv11-architect.png',        'level_11_architect'),
  ('level_12_nether',      'level',   '冥语者', 12, 'badges', 'final/lv12-nether-speaker.png',   'level_12_nether'),
  ('level_13_wasteport',   'level',   '荒港客', 13, 'badges', 'final/lv13-wasteport-guest.png',  'level_13_wasteport'),
  ('level_14_alchemist',   'level',   '炼金士', 14, 'badges', 'final/lv14-alchemist.png',        'level_14_alchemist'),
  ('level_15_maskman',     'level',   '面具人', 15, 'badges', 'final/lv15-maskman.png',          'level_15_maskman'),
  ('level_16_godslayer',   'level',   '弑神者', 16, 'badges', 'final/lv16-godslayer.png',        'level_16_godslayer'),
  ('founder',              'founder', '开创者', NULL, 'badges', 'final/founder-v21.png',         'founder')
ON CONFLICT (badge_key) DO UPDATE SET
  badge_type = EXCLUDED.badge_type,
  title = EXCLUDED.title,
  level = EXCLUDED.level,
  image_bucket = EXCLUDED.image_bucket,
  image_path = EXCLUDED.image_path,
  riddle_key = EXCLUDED.riddle_key,
  is_active = true,
  updated_at = now();

-- ------------------------------------------------------------
-- 3. 用户会员汇总、徽章、资源浏览券、共读兑换券
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_stats (
  user_id                 UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  level                   INTEGER NOT NULL DEFAULT 0 REFERENCES public.member_levels(level),
  tier                    TEXT NOT NULL DEFAULT '基础会员',
  contribution_total      INTEGER NOT NULL DEFAULT 0,
  contribution_month      INTEGER NOT NULL DEFAULT 0,
  contribution_week       INTEGER NOT NULL DEFAULT 0,
  current_badge_key       TEXT REFERENCES public.badge_catalog(badge_key),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT member_stats_contribution_nonnegative CHECK (
    contribution_total >= 0 AND contribution_month >= 0 AND contribution_week >= 0
  )
);

CREATE INDEX IF NOT EXISTS idx_member_stats_level ON public.member_stats(level);
CREATE INDEX IF NOT EXISTS idx_member_stats_total ON public.member_stats(contribution_total DESC);
CREATE INDEX IF NOT EXISTS idx_member_stats_week ON public.member_stats(contribution_week DESC);

ALTER TABLE public.member_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "member_stats_read_self_or_admin" ON public.member_stats;
CREATE POLICY "member_stats_read_self_or_admin" ON public.member_stats FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "member_stats_admin_write" ON public.member_stats;
CREATE POLICY "member_stats_admin_write" ON public.member_stats FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.user_badges (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key         TEXT NOT NULL REFERENCES public.badge_catalog(badge_key),
  badge_type        TEXT NOT NULL CHECK (badge_type IN ('level', 'founder', 'commemorative', 'behavior')),
  awarded_reason    TEXT,
  awarded_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at        TIMESTAMPTZ,
  UNIQUE(user_id, badge_key)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON public.user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_badge ON public.user_badges(badge_key);

ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user_badges_read_self_or_admin" ON public.user_badges;
CREATE POLICY "user_badges_read_self_or_admin" ON public.user_badges FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "user_badges_admin_write" ON public.user_badges;
CREATE POLICY "user_badges_admin_write" ON public.user_badges FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.view_passes (
  id                           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id                      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status                       TEXT NOT NULL DEFAULT 'available'
                               CHECK (status IN ('available', 'used', 'expired', 'revoked')),
  issued_reason                TEXT NOT NULL
                               CHECK (issued_reason IN ('signup', 'weekly', 'active_bonus', 'admin')),
  source_key                   TEXT,
  issued_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at                   TIMESTAMPTZ NOT NULL,
  used_at                      TIMESTAMPTZ,
  used_resource_key            TEXT,
  temporary_access_expires_at  TIMESTAMPTZ,
  revoked_at                   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_view_passes_user_status ON public.view_passes(user_id, status);
CREATE INDEX IF NOT EXISTS idx_view_passes_expires ON public.view_passes(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_view_passes_user_source_key
  ON public.view_passes(user_id, source_key)
  WHERE source_key IS NOT NULL;

ALTER TABLE public.view_passes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "view_passes_read_self_or_admin" ON public.view_passes;
CREATE POLICY "view_passes_read_self_or_admin" ON public.view_passes FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "view_passes_admin_write" ON public.view_passes;
CREATE POLICY "view_passes_admin_write" ON public.view_passes FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.resource_redemption_tickets (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available', 'used', 'revoked')),
  issued_level    INTEGER REFERENCES public.member_levels(level),
  issued_reason   TEXT NOT NULL CHECK (issued_reason IN ('level_up', 'admin')),
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at         TIMESTAMPTZ,
  used_book_id    BIGINT REFERENCES public.books(id),
  revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_redemption_tickets_user_status
  ON public.resource_redemption_tickets(user_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_redemption_level_reward_once
  ON public.resource_redemption_tickets(user_id, issued_level)
  WHERE issued_reason = 'level_up';

ALTER TABLE public.resource_redemption_tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "redemption_tickets_read_self_or_admin" ON public.resource_redemption_tickets;
CREATE POLICY "redemption_tickets_read_self_or_admin" ON public.resource_redemption_tickets FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "redemption_tickets_admin_write" ON public.resource_redemption_tickets;
CREATE POLICY "redemption_tickets_admin_write" ON public.resource_redemption_tickets FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- 4. 初始化、等级重算与注册触发
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.initialize_member_for_user(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.member_stats (
    user_id,
    level,
    tier,
    contribution_total,
    contribution_month,
    contribution_week,
    current_badge_key
  )
  VALUES (
    p_user_id,
    0,
    '基础会员',
    0,
    0,
    0,
    NULL
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.view_passes (
    user_id,
    status,
    issued_reason,
    source_key,
    issued_at,
    expires_at
  )
  VALUES (
    p_user_id,
    'available',
    'signup',
    'signup_initial_view_pass',
    now(),
    now() + interval '7 days'
  )
  ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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

  IF v_new_level > COALESCE(v_old_level, 0) THEN
    INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
    SELECT p_user_id, ml.badge_key, 'level', 'level_up'
    FROM public.member_levels ml
    WHERE ml.level > COALESCE(v_old_level, 0)
      AND ml.level <= v_new_level
      AND ml.badge_key IS NOT NULL
    ON CONFLICT (user_id, badge_key) DO UPDATE SET
      revoked_at = NULL,
      awarded_reason = EXCLUDED.awarded_reason;

    INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
    SELECT p_user_id, 'available', ml.level, 'level_up'
    FROM public.member_levels ml
    WHERE ml.level > COALESCE(v_old_level, 0)
      AND ml.level <= v_new_level
      AND ml.reward_redemption_tickets > 0
    ON CONFLICT DO NOTHING;
  ELSIF v_new_level < COALESCE(v_old_level, 0) THEN
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

-- 新用户注册时：创建 profile + 初始化会员状态 + 发首次资源浏览券
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email))
  ON CONFLICT (id) DO NOTHING;

  PERFORM public.initialize_member_for_user(NEW.id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 为历史用户补齐会员状态和首次资源浏览券
SELECT public.initialize_member_for_user(id)
FROM public.profiles;

-- ------------------------------------------------------------
-- 5. 权限说明
-- ------------------------------------------------------------
COMMENT ON TABLE public.member_levels IS '会员等级配置：Lv.0-Lv.16、段位、贡献值区间和每周资源浏览券数量';
COMMENT ON TABLE public.member_stats IS '用户会员汇总：等级、段位、贡献值和当前等级徽章';
COMMENT ON TABLE public.badge_catalog IS '徽章配置：等级成长徽章、开创者徽章和后续纪念 / 行为徽章';
COMMENT ON TABLE public.user_badges IS '用户已获得徽章记录';
COMMENT ON TABLE public.view_passes IS '资源浏览券：首次注册、每周发放、活跃奖励或管理员发放';
COMMENT ON TABLE public.resource_redemption_tickets IS '共读兑换券：升级或管理员发放，用于后续永久解锁历史共读资源';
