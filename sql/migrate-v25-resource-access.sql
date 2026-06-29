-- ============================================================
-- 以读攻独 · v25 迁移：资源权限与票券解锁
-- 永久权限按 book_id 授予；临时权限按 resource_key 授予 72 小时
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.resource_access_grants (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  book_id         BIGINT NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  resource_scope  TEXT NOT NULL DEFAULT 'book' CHECK (resource_scope IN ('book', 'resource')),
  resource_key    TEXT,
  grant_type      TEXT NOT NULL CHECK (grant_type IN ('commemorative', 'redeemed', 'founder', 'admin')),
  source_id       BIGINT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_resource_access_user_book
  ON public.resource_access_grants(user_id, book_id)
  WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_access_unique_active_book
  ON public.resource_access_grants(user_id, book_id, resource_scope)
  WHERE revoked_at IS NULL AND resource_scope = 'book';

ALTER TABLE public.resource_access_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "resource_access_read_self_or_admin" ON public.resource_access_grants;
CREATE POLICY "resource_access_read_self_or_admin"
  ON public.resource_access_grants FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "resource_access_admin_write" ON public.resource_access_grants;
CREATE POLICY "resource_access_admin_write"
  ON public.resource_access_grants FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.expire_view_passes_for_user(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.view_passes
  SET status = 'expired',
      revoked_at = COALESCE(revoked_at, now())
  WHERE user_id = p_user_id
    AND status = 'available'
    AND expires_at <= now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT false, 0, 0, ARRAY[]::TEXT[];
    RETURN;
  END IF;

  PERFORM public.expire_view_passes_for_user(v_user_id);

  SELECT public.is_admin() INTO v_is_admin;

  RETURN QUERY
  SELECT
    (
      COALESCE(v_is_admin, false)
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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

  IF public.is_admin() OR EXISTS (
    SELECT 1
    FROM public.resource_access_grants rag
    WHERE rag.user_id = v_user_id
      AND rag.book_id = p_book_id
      AND rag.resource_scope = 'book'
      AND rag.revoked_at IS NULL
  ) THEN
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

CREATE OR REPLACE FUNCTION public.redeem_book_access(p_book_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_ticket_id BIGINT;
  v_grant_id BIGINT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT rag.id
    INTO v_grant_id
  FROM public.resource_access_grants rag
  WHERE rag.user_id = v_user_id
    AND rag.book_id = p_book_id
    AND rag.resource_scope = 'book'
    AND rag.revoked_at IS NULL
  LIMIT 1;

  IF v_grant_id IS NOT NULL THEN
    RETURN v_grant_id;
  END IF;

  SELECT rt.id
    INTO v_ticket_id
  FROM public.resource_redemption_tickets rt
  WHERE rt.user_id = v_user_id
    AND rt.status = 'available'
  ORDER BY rt.issued_at ASC
  LIMIT 1
  FOR UPDATE;

  IF v_ticket_id IS NULL THEN
    RAISE EXCEPTION 'No available redemption ticket';
  END IF;

  UPDATE public.resource_redemption_tickets
  SET status = 'used',
      used_at = now(),
      used_book_id = p_book_id
  WHERE id = v_ticket_id;

  INSERT INTO public.resource_access_grants
    (user_id, book_id, resource_scope, grant_type, source_id)
  VALUES
    (v_user_id, p_book_id, 'book', 'redeemed', v_ticket_id)
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_resource_access_summary(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_view_pass(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_book_access(BIGINT) TO authenticated;

COMMENT ON TABLE public.resource_access_grants IS
  '受保护资源永久权限：第一版按 book_id 授权整本书 / 整期共读资源';
