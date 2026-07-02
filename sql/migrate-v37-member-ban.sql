-- ============================================================
-- 以读攻独 · v37 迁移：会员封禁
-- 管理员可在会员清单中封禁/解锁用户。
-- 封禁后，该账号不能浏览共读书库、书友圈、西语文学板块，也不能在书友圈发帖互动。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_bans (
  user_id     UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL DEFAULT '',
  banned_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  banned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  lifted_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  lifted_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_member_bans_active
  ON public.member_bans(user_id)
  WHERE lifted_at IS NULL;

ALTER TABLE public.member_bans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_bans_admin_read" ON public.member_bans;
CREATE POLICY "member_bans_admin_read"
  ON public.member_bans
  FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "member_bans_admin_write" ON public.member_bans;
CREATE POLICY "member_bans_admin_write"
  ON public.member_bans
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.is_user_banned(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.member_bans mb
    WHERE mb.user_id = p_user_id
      AND mb.lifted_at IS NULL
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_current_user_banned()
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NULL OR public.is_admin() THEN
    RETURN false;
  END IF;

  RETURN public.is_user_banned(auth.uid());
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.require_not_banned()
RETURNS VOID AS $$
BEGIN
  IF public.is_current_user_banned() THEN
    RAISE EXCEPTION 'account_banned';
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.require_authenticated_member()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'login_required';
  END IF;

  PERFORM public.require_not_banned();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_set_member_ban(
  p_user_id UUID,
  p_is_banned BOOLEAN,
  p_reason TEXT DEFAULT ''
)
RETURNS VOID AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  IF p_user_id = auth.uid() AND p_is_banned THEN
    RAISE EXCEPTION 'cannot_ban_self';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  IF p_is_banned THEN
    INSERT INTO public.member_bans
      (user_id, reason, banned_by, banned_at, lifted_by, lifted_at)
    VALUES
      (p_user_id, COALESCE(p_reason, ''), auth.uid(), now(), NULL, NULL)
    ON CONFLICT (user_id) DO UPDATE SET
      reason = EXCLUDED.reason,
      banned_by = auth.uid(),
      banned_at = now(),
      lifted_by = NULL,
      lifted_at = NULL;
  ELSE
    UPDATE public.member_bans
    SET lifted_by = auth.uid(),
        lifted_at = now()
    WHERE user_id = p_user_id
      AND lifted_at IS NULL;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 被封禁用户不可读取共读书库；游客仍可浏览公开书库。
DROP POLICY IF EXISTS "books_read_all" ON public.books;
DROP POLICY IF EXISTS "books_read_public_not_banned" ON public.books;
CREATE POLICY "books_read_public_not_banned"
  ON public.books
  FOR SELECT
  USING (
    auth.uid() IS NULL
    OR public.is_admin()
    OR NOT public.is_user_banned(auth.uid())
  );

-- 书友圈写入兜底：阻断被封禁用户绕过前端直接调用 RPC。
CREATE OR REPLACE FUNCTION public.block_banned_reading_circle_write()
RETURNS TRIGGER AS $$
BEGIN
  IF public.is_current_user_banned() THEN
    RAISE EXCEPTION 'account_banned';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_block_banned_reading_posts_write ON public.reading_posts;
CREATE TRIGGER trg_block_banned_reading_posts_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.reading_posts
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

DROP TRIGGER IF EXISTS trg_block_banned_post_comments_write ON public.post_comments;
CREATE TRIGGER trg_block_banned_post_comments_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.post_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

DROP TRIGGER IF EXISTS trg_block_banned_post_likes_write ON public.post_likes;
CREATE TRIGGER trg_block_banned_post_likes_write
  BEFORE INSERT OR DELETE ON public.post_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.block_banned_reading_circle_write();

-- 会员清单增加封禁状态；改返回类型需要先删除旧函数。
DROP FUNCTION IF EXISTS public.admin_list_members();

CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  registered_at TIMESTAMPTZ,
  level INTEGER,
  title TEXT,
  tier TEXT,
  note TEXT,
  is_banned BOOLEAN,
  ban_reason TEXT,
  banned_at TIMESTAMPTZ
) AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.display_name,
    au.email::TEXT AS email,
    COALESCE(au.created_at, p.created_at) AS registered_at,
    COALESCE(ms.level, 0) AS level,
    ml.title,
    COALESCE(ms.tier, ml.tier, '基础会员') AS tier,
    COALESCE(man.note, '') AS note,
    (mb.user_id IS NOT NULL) AS is_banned,
    COALESCE(mb.reason, '') AS ban_reason,
    mb.banned_at
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  LEFT JOIN public.member_admin_notes man ON man.user_id = p.id
  LEFT JOIN public.member_bans mb ON mb.user_id = p.id AND mb.lifted_at IS NULL
  ORDER BY COALESCE(au.created_at, p.created_at) DESC, p.display_name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_current_user_banned() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_member_ban(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_members() TO authenticated;

COMMENT ON TABLE public.member_bans IS '会员封禁记录；lifted_at 为空代表当前封禁中';
COMMENT ON FUNCTION public.admin_set_member_ban(UUID, BOOLEAN, TEXT) IS '管理员封禁或解锁会员';
