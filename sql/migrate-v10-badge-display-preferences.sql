-- ============================================================
-- 以读攻独 · v10 迁移：用户个人中心徽章展示偏好
-- 支持用户在“更多徽章”页选择最多 6 枚徽章展示在个人中心
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_badge_display_preferences (
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  badge_key   TEXT NOT NULL REFERENCES public.badge_catalog(badge_key) ON DELETE CASCADE,
  sort_order  INTEGER NOT NULL CHECK (sort_order BETWEEN 1 AND 6),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, badge_key),
  UNIQUE (user_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_member_badge_display_user_order
  ON public.member_badge_display_preferences(user_id, sort_order);

CREATE OR REPLACE FUNCTION public.check_member_badge_display_preference()
RETURNS TRIGGER AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_badges ub
    WHERE ub.user_id = NEW.user_id
      AND ub.badge_key = NEW.badge_key
      AND ub.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot display a badge that the user has not earned';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.member_badge_display_preferences p
    WHERE p.user_id = NEW.user_id
      AND p.badge_key <> NEW.badge_key
  ) >= 6 THEN
    RAISE EXCEPTION 'A user can display at most 6 badges';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_member_badge_display_preference_check
  ON public.member_badge_display_preferences;
CREATE TRIGGER trg_member_badge_display_preference_check
  BEFORE INSERT OR UPDATE ON public.member_badge_display_preferences
  FOR EACH ROW EXECUTE FUNCTION public.check_member_badge_display_preference();

ALTER TABLE public.member_badge_display_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badge_display_read_self_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_read_self_or_admin"
  ON public.member_badge_display_preferences
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "badge_display_insert_self_earned_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_insert_self_earned_or_admin"
  ON public.member_badge_display_preferences
  FOR INSERT
  WITH CHECK (
    public.is_admin()
    OR (
      auth.uid() = user_id
      AND EXISTS (
        SELECT 1
        FROM public.user_badges ub
        WHERE ub.user_id = member_badge_display_preferences.user_id
          AND ub.badge_key = member_badge_display_preferences.badge_key
          AND ub.revoked_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "badge_display_update_self_earned_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_update_self_earned_or_admin"
  ON public.member_badge_display_preferences
  FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (
    public.is_admin()
    OR (
      auth.uid() = user_id
      AND EXISTS (
        SELECT 1
        FROM public.user_badges ub
        WHERE ub.user_id = member_badge_display_preferences.user_id
          AND ub.badge_key = member_badge_display_preferences.badge_key
          AND ub.revoked_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "badge_display_delete_self_or_admin"
  ON public.member_badge_display_preferences;
CREATE POLICY "badge_display_delete_self_or_admin"
  ON public.member_badge_display_preferences
  FOR DELETE
  USING (auth.uid() = user_id OR public.is_admin());

COMMENT ON TABLE public.member_badge_display_preferences IS
  '用户个人中心徽章展示偏好：每人最多选择 6 枚已获得徽章';
