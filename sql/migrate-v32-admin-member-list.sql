-- ============================================================
-- 以读攻独 · v32 迁移：管理后台会员清单与备注
-- 管理员可查看会员 UID / 昵称 / email / 注册时间 / 等级，并维护备注
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_admin_notes (
  user_id     UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  note        TEXT NOT NULL DEFAULT '',
  created_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.member_admin_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_admin_notes_admin_read" ON public.member_admin_notes;
CREATE POLICY "member_admin_notes_admin_read"
  ON public.member_admin_notes
  FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "member_admin_notes_admin_write" ON public.member_admin_notes;
CREATE POLICY "member_admin_notes_admin_write"
  ON public.member_admin_notes
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  registered_at TIMESTAMPTZ,
  level INTEGER,
  title TEXT,
  tier TEXT,
  note TEXT
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
    COALESCE(man.note, '') AS note
  FROM public.profiles p
  LEFT JOIN auth.users au ON au.id = p.id
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  LEFT JOIN public.member_admin_notes man ON man.user_id = p.id
  ORDER BY COALESCE(au.created_at, p.created_at) DESC, p.display_name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_update_member_note(
  p_user_id UUID,
  p_note TEXT
)
RETURNS public.member_admin_notes AS $$
DECLARE
  v_row public.member_admin_notes%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  INSERT INTO public.member_admin_notes
    (user_id, note, created_by, updated_by, created_at, updated_at)
  VALUES
    (p_user_id, COALESCE(p_note, ''), auth.uid(), auth.uid(), now(), now())
  ON CONFLICT (user_id) DO UPDATE SET
    note = EXCLUDED.note,
    updated_by = auth.uid(),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.admin_list_members() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_member_note(UUID, TEXT) TO authenticated;

COMMENT ON TABLE public.member_admin_notes IS '管理员维护的会员后台备注，仅管理员可见';
COMMENT ON FUNCTION public.admin_list_members() IS '管理员后台会员清单，包含 auth.users.email 与会员等级';
COMMENT ON FUNCTION public.admin_update_member_note(UUID, TEXT) IS '管理员更新单个会员备注';
