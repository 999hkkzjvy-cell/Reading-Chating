-- ============================================================
-- 以读攻独 · v26 迁移：共读密码、纪念券、纪念徽章与周券发放
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- 1. 书籍加入页配置
-- ------------------------------------------------------------
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_intro TEXT;

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS join_qr_url TEXT;

-- ------------------------------------------------------------
-- 2. 共读密码与领取记录
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.co_reading_passwords (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  book_id       BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  label         TEXT NOT NULL DEFAULT '共读密码',
  password_hash TEXT NOT NULL,
  password_plain TEXT,
  starts_at     TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_by    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_co_reading_passwords_book
  ON public.co_reading_passwords(book_id, is_active);

ALTER TABLE public.co_reading_passwords ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "co_reading_passwords_admin_read" ON public.co_reading_passwords;
CREATE POLICY "co_reading_passwords_admin_read"
  ON public.co_reading_passwords FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "co_reading_passwords_admin_write" ON public.co_reading_passwords;
CREATE POLICY "co_reading_passwords_admin_write"
  ON public.co_reading_passwords FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.co_reading_claims (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  password_id     BIGINT REFERENCES public.co_reading_passwords(id) ON DELETE SET NULL,
  group_member_id TEXT NOT NULL,
  claimed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_co_reading_claims_book
  ON public.co_reading_claims(book_id, claimed_at DESC);

ALTER TABLE public.co_reading_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "co_reading_claims_read_self_or_admin" ON public.co_reading_claims;
CREATE POLICY "co_reading_claims_read_self_or_admin"
  ON public.co_reading_claims FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "co_reading_claims_admin_write" ON public.co_reading_claims;
CREATE POLICY "co_reading_claims_admin_write"
  ON public.co_reading_claims FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.commemorative_tickets (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  claim_id        BIGINT REFERENCES public.co_reading_claims(id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  group_member_id TEXT,
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at      TIMESTAMPTZ,
  UNIQUE(user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_commemorative_tickets_user
  ON public.commemorative_tickets(user_id, status);

ALTER TABLE public.commemorative_tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "commemorative_tickets_read_self_or_admin" ON public.commemorative_tickets;
CREATE POLICY "commemorative_tickets_read_self_or_admin"
  ON public.commemorative_tickets FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "commemorative_tickets_admin_write" ON public.commemorative_tickets;
CREATE POLICY "commemorative_tickets_admin_write"
  ON public.commemorative_tickets FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- 3. 开创者徽章即权限
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_founder_badge(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.user_badges ub
    JOIN public.badge_catalog bc ON bc.badge_key = ub.badge_key
    WHERE ub.user_id = p_user_id
      AND ub.revoked_at IS NULL
      AND (ub.badge_key = 'founder' OR ub.badge_type = 'founder' OR bc.badge_type = 'founder')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.get_resource_access_summary(p_book_id BIGINT)
RETURNS TABLE (
  has_permanent_access BOOLEAN,
  available_view_passes INTEGER,
  available_redemption_tickets INTEGER,
  temporary_resource_keys TEXT[]
) AS $$
DECLARE
  v_user_id UUID;
  v_is_admin BOOLEAN;
  v_is_founder BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, 0, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT public.is_admin() INTO v_is_admin;
  SELECT public.has_founder_badge(v_user_id) INTO v_is_founder;

  RETURN QUERY
  SELECT
    (
      COALESCE(v_is_admin, false)
      OR COALESCE(v_is_founder, false)
      OR EXISTS (
        SELECT 1
        FROM public.resource_access_grants rag
        WHERE rag.user_id = v_user_id
          AND rag.book_id = p_book_id
          AND rag.resource_scope = 'book'
          AND rag.revoked_at IS NULL
      )
    ) AS has_permanent_access,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'available'
        AND vp.expires_at > now()
    ) AS available_view_passes,
    (
      SELECT COUNT(*)::INTEGER
      FROM public.resource_redemption_tickets rt
      WHERE rt.user_id = v_user_id
        AND rt.status = 'available'
    ) AS available_redemption_tickets,
    COALESCE((
      SELECT array_agg(vp.used_resource_key)
      FROM public.view_passes vp
      WHERE vp.user_id = v_user_id
        AND vp.status = 'used'
        AND vp.used_resource_key IS NOT NULL
        AND vp.temporary_access_expires_at > now()
        AND vp.used_resource_key LIKE ('book:' || p_book_id || ':%')
    ), ARRAY[]::TEXT[]) AS temporary_resource_keys;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.consume_view_pass(
  p_book_id BIGINT,
  p_resource_key TEXT
)
RETURNS TIMESTAMPTZ AS $$
DECLARE
  v_user_id UUID;
  v_pass_id BIGINT;
  v_existing_expires TIMESTAMPTZ;
  v_new_expires TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_resource_key IS NULL OR p_resource_key !~ ('^book:' || p_book_id || ':') THEN
    RAISE EXCEPTION 'Invalid resource key';
  END IF;

  IF public.is_admin()
    OR public.has_founder_badge(v_user_id)
    OR EXISTS (
      SELECT 1
      FROM public.resource_access_grants rag
      WHERE rag.user_id = v_user_id
        AND rag.book_id = p_book_id
        AND rag.resource_scope = 'book'
        AND rag.revoked_at IS NULL
    )
  THEN
    RETURN now() + interval '100 years';
  END IF;

  SELECT vp.temporary_access_expires_at
    INTO v_existing_expires
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'used'
    AND vp.used_resource_key = p_resource_key
    AND vp.temporary_access_expires_at > now()
  ORDER BY vp.temporary_access_expires_at DESC
  LIMIT 1;

  IF v_existing_expires IS NOT NULL THEN
    RETURN v_existing_expires;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT vp.id
    INTO v_pass_id
  FROM public.view_passes vp
  WHERE vp.user_id = v_user_id
    AND vp.status = 'available'
    AND vp.expires_at > now()
  ORDER BY vp.expires_at ASC, vp.issued_at ASC
  LIMIT 1
  FOR UPDATE;

  IF v_pass_id IS NULL THEN
    RAISE EXCEPTION 'No available view pass';
  END IF;

  v_new_expires := now() + interval '72 hours';

  UPDATE public.view_passes
  SET status = 'used',
      used_at = now(),
      used_resource_key = p_resource_key,
      temporary_access_expires_at = v_new_expires
  WHERE id = v_pass_id;

  RETURN v_new_expires;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ------------------------------------------------------------
-- 4. 共读纪念徽章与密码核销
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_commemorative_badges(p_book_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_title TEXT;
BEGIN
  SELECT title INTO v_title
  FROM public.books
  WHERE id = p_book_id;

  IF v_title IS NULL THEN
    RAISE EXCEPTION 'Book not found';
  END IF;

  INSERT INTO public.badge_catalog
    (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
  VALUES
    ('commemorative_book_' || p_book_id || '_claimed', 'commemorative', '《' || v_title || '》共读纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_claimed'),
    ('commemorative_book_' || p_book_id || '_finished', 'commemorative', '《' || v_title || '》读完纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_finished')
  ON CONFLICT (badge_key) DO UPDATE SET
    title = EXCLUDED.title,
    badge_type = EXCLUDED.badge_type,
    is_active = true,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_create_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_label TEXT DEFAULT '共读密码',
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  IF trim(COALESCE(p_password, '')) = '' THEN
    RAISE EXCEPTION 'Password is required';
  END IF;

  INSERT INTO public.co_reading_passwords
    (book_id, label, password_hash, password_plain, starts_at, expires_at, created_by)
  VALUES
    (p_book_id, COALESCE(NULLIF(trim(COALESCE(p_label, '')), ''), '共读密码'), crypt(trim(p_password), gen_salt('bf')), trim(p_password), p_starts_at, p_expires_at, auth.uid())
  RETURNING id INTO v_id;

  PERFORM public.ensure_commemorative_badges(p_book_id);
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_set_co_reading_password_active(
  p_password_id BIGINT,
  p_is_active BOOLEAN
)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  UPDATE public.co_reading_passwords
  SET is_active = p_is_active,
      updated_at = now()
  WHERE id = p_password_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.claim_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_group_member_id TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_password_id BIGINT;
  v_claim_id BIGINT;
  v_ticket_id BIGINT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_group_member_id, '')) = '' THEN
    RAISE EXCEPTION 'Group member id is required';
  END IF;

  SELECT id INTO v_claim_id
  FROM public.co_reading_claims
  WHERE user_id = v_user_id
    AND book_id = p_book_id
  LIMIT 1;

  IF v_claim_id IS NOT NULL THEN
    RETURN v_claim_id;
  END IF;

  SELECT id INTO v_password_id
  FROM public.co_reading_passwords
  WHERE book_id = p_book_id
    AND is_active = true
    AND (starts_at IS NULL OR starts_at <= now())
    AND (expires_at IS NULL OR expires_at >= now())
    AND password_hash = crypt(trim(COALESCE(p_password, '')), password_hash)
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_password_id IS NULL THEN
    RAISE EXCEPTION 'Invalid co-reading password';
  END IF;

  PERFORM public.ensure_commemorative_badges(p_book_id);

  INSERT INTO public.co_reading_claims
    (user_id, book_id, password_id, group_member_id)
  VALUES
    (v_user_id, p_book_id, v_password_id, trim(p_group_member_id))
  RETURNING id INTO v_claim_id;

  INSERT INTO public.commemorative_tickets
    (user_id, book_id, claim_id, group_member_id)
  VALUES
    (v_user_id, p_book_id, v_claim_id, trim(p_group_member_id))
  ON CONFLICT (user_id, book_id) DO UPDATE SET
    status = 'active',
    revoked_at = NULL
  RETURNING id INTO v_ticket_id;

  INSERT INTO public.resource_access_grants
    (user_id, book_id, resource_scope, grant_type, source_id)
  VALUES
    (v_user_id, p_book_id, 'book', 'commemorative', v_claim_id)
  ON CONFLICT (user_id, book_id, resource_scope)
    WHERE revoked_at IS NULL AND resource_scope = 'book'
  DO NOTHING;

  INSERT INTO public.user_badges
    (user_id, badge_key, badge_type, awarded_reason)
  VALUES
    (v_user_id, 'commemorative_book_' || p_book_id || '_claimed', 'commemorative', 'co_reading_password_claim')
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  RETURN v_claim_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.award_finished_commemorative_badge()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.post_type = 'finished'
    AND NEW.linked_book_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.commemorative_tickets ct
      WHERE ct.user_id = NEW.user_id
        AND ct.book_id = NEW.linked_book_id
        AND ct.status = 'active'
    )
  THEN
    PERFORM public.ensure_commemorative_badges(NEW.linked_book_id);

    INSERT INTO public.user_badges
      (user_id, badge_key, badge_type, awarded_reason)
    VALUES
      (NEW.user_id, 'commemorative_book_' || NEW.linked_book_id || '_finished', 'commemorative', 'finished_reading_post')
    ON CONFLICT (user_id, badge_key) DO UPDATE SET
      revoked_at = NULL,
      awarded_reason = EXCLUDED.awarded_reason;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_award_finished_commemorative_badge ON public.reading_posts;
CREATE TRIGGER trg_award_finished_commemorative_badge
AFTER INSERT OR UPDATE OF post_type, linked_book_id ON public.reading_posts
FOR EACH ROW
EXECUTE FUNCTION public.award_finished_commemorative_badge();

-- ------------------------------------------------------------
-- 5. 管理员一键发放本周资源浏览券
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_issue_weekly_view_passes()
RETURNS TABLE (
  issued_users INTEGER,
  issued_passes INTEGER,
  source_key TEXT
) AS $$
DECLARE
  v_source_key TEXT;
  v_inserted INTEGER;
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
      row_number() OVER (ORDER BY COALESCE(wa.points, 0) DESC, ms.contribution_total DESC, ms.user_id) AS rank_position
    FROM public.member_stats ms
    JOIN public.member_levels ml ON ml.level = ms.level
    LEFT JOIN weekly_activity wa ON wa.user_id = ms.user_id
    WHERE ml.weekly_view_passes > 0
  ),
  expanded AS (
    SELECT
      r.user_id,
      generate_series(1, r.weekly_view_passes * CASE WHEN r.weekly_activity_points > 0 AND r.rank_position <= 5 THEN 2 ELSE 1 END) AS pass_no
    FROM ranked r
  ),
  inserted AS (
    INSERT INTO public.view_passes
      (user_id, status, issued_reason, source_key, issued_at, expires_at)
    SELECT
      e.user_id,
      'available',
      'weekly',
      v_source_key || '_' || e.user_id || '_' || e.pass_no,
      now(),
      now() + interval '7 days'
    FROM expanded e
    ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING
    RETURNING user_id
  )
  SELECT COUNT(*)::INTEGER, COUNT(DISTINCT user_id)::INTEGER
    INTO v_inserted, issued_users
  FROM inserted;

  issued_passes := COALESCE(v_inserted, 0);
  source_key := v_source_key;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.has_founder_badge(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_resource_access_summary(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_view_pass(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_co_reading_password(BIGINT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_co_reading_password_active(BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_co_reading_password(BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_issue_weekly_view_passes() TO authenticated;

COMMENT ON TABLE public.co_reading_passwords IS '按书籍 / 共读期配置的共读密码，hash 用于核销，password_plain 仅管理员后台展示';
COMMENT ON TABLE public.co_reading_claims IS '用户核销共读密码记录，包含群内 ID';
COMMENT ON TABLE public.commemorative_tickets IS '共读纪念券，激活对应书籍 / 共读期永久资源权限';
