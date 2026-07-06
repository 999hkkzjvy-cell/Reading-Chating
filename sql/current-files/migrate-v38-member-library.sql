-- ============================================================
-- 以读攻独 · v38 迁移：我的书库
-- 已读书目来自已读书友圈；想读书目最多 5 本；人生之书最多 3 本。
-- 管理员可导出当前所有会员想读 / 人生之书数据。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.member_library_items (
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  list_type   TEXT NOT NULL CHECK (list_type IN ('want', 'life')),
  sort_order  INTEGER NOT NULL,
  book_title  TEXT NOT NULL,
  author      TEXT,
  douban_url  TEXT NOT NULL,
  cover_url   TEXT,
  reason      TEXT NOT NULL DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, list_type, sort_order),
  CONSTRAINT member_library_items_sort_limit CHECK (
    (list_type = 'want' AND sort_order BETWEEN 1 AND 5)
    OR (list_type = 'life' AND sort_order BETWEEN 1 AND 3)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_member_library_unique_book
  ON public.member_library_items(user_id, list_type, douban_url);

CREATE INDEX IF NOT EXISTS idx_member_library_user_type
  ON public.member_library_items(user_id, list_type, sort_order);

ALTER TABLE public.member_library_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_library_read_self_or_admin" ON public.member_library_items;
CREATE POLICY "member_library_read_self_or_admin"
  ON public.member_library_items
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "member_library_write_self" ON public.member_library_items;
CREATE POLICY "member_library_write_self"
  ON public.member_library_items
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.list_my_finished_books()
RETURNS TABLE (
  post_id BIGINT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  content TEXT,
  visibility TEXT,
  finished_at TIMESTAMPTZ,
  post_count BIGINT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH finished AS (
    SELECT
      rp.*,
      COALESCE(NULLIF(trim(rp.douban_url), ''), 'title:' || lower(trim(rp.book_title))) AS book_key
    FROM public.reading_posts rp
    WHERE rp.user_id = auth.uid()
      AND rp.post_type = 'finished'
      AND rp.is_deleted = false
  ),
  ranked AS (
    SELECT
      f.*,
      row_number() OVER (PARTITION BY f.book_key ORDER BY f.created_at DESC, f.id DESC) AS rn,
      count(*) OVER (PARTITION BY f.book_key) AS post_count
    FROM finished f
  )
  SELECT
    r.id,
    r.book_title,
    r.author,
    r.douban_url,
    r.cover_url,
    r.content,
    r.visibility,
    r.created_at,
    r.post_count
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.created_at DESC, r.id DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_my_member_library_items()
RETURNS TABLE (
  list_type TEXT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  reason TEXT,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    mli.list_type,
    mli.sort_order,
    mli.book_title,
    mli.author,
    mli.douban_url,
    mli.cover_url,
    mli.reason,
    mli.updated_at
  FROM public.member_library_items mli
  WHERE mli.user_id = auth.uid()
  ORDER BY mli.list_type, mli.sort_order;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.upsert_my_member_library_item(
  p_list_type TEXT,
  p_sort_order INTEGER,
  p_book_title TEXT,
  p_author TEXT,
  p_douban_url TEXT,
  p_cover_url TEXT DEFAULT NULL,
  p_reason TEXT DEFAULT ''
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_douban_url TEXT;
BEGIN
  PERFORM public.require_authenticated_member();
  v_user_id := auth.uid();

  IF p_list_type NOT IN ('want', 'life') THEN
    RAISE EXCEPTION 'invalid_list_type';
  END IF;

  IF (p_list_type = 'want' AND (p_sort_order < 1 OR p_sort_order > 5))
    OR (p_list_type = 'life' AND (p_sort_order < 1 OR p_sort_order > 3)) THEN
    RAISE EXCEPTION 'invalid_sort_order';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'book_title_required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = '' OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?' THEN
    RAISE EXCEPTION 'valid_douban_url_required';
  END IF;

  DELETE FROM public.member_library_items
  WHERE user_id = v_user_id
    AND list_type = p_list_type
    AND douban_url = v_douban_url
    AND sort_order <> p_sort_order;

  INSERT INTO public.member_library_items (
    user_id, list_type, sort_order, book_title, author, douban_url, cover_url, reason, created_at, updated_at
  ) VALUES (
    v_user_id,
    p_list_type,
    p_sort_order,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url,
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    COALESCE(p_reason, ''),
    now(),
    now()
  )
  ON CONFLICT (user_id, list_type, sort_order) DO UPDATE SET
    book_title = EXCLUDED.book_title,
    author = EXCLUDED.author,
    douban_url = EXCLUDED.douban_url,
    cover_url = EXCLUDED.cover_url,
    reason = EXCLUDED.reason,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.delete_my_member_library_item(
  p_list_type TEXT,
  p_sort_order INTEGER
)
RETURNS VOID AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  DELETE FROM public.member_library_items
  WHERE user_id = auth.uid()
    AND list_type = p_list_type
    AND sort_order = p_sort_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.admin_export_member_library()
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  email TEXT,
  list_type TEXT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  reason TEXT,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  RETURN QUERY
  SELECT
    mli.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    au.email::TEXT AS email,
    mli.list_type,
    mli.sort_order,
    mli.book_title,
    mli.author,
    mli.douban_url,
    mli.reason,
    mli.updated_at
  FROM public.member_library_items mli
  LEFT JOIN public.profiles p ON p.id = mli.user_id
  LEFT JOIN auth.users au ON au.id = mli.user_id
  ORDER BY mli.list_type, mli.sort_order, mli.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_my_finished_books() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_member_library_items() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_my_member_library_item(TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_member_library_item(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_export_member_library() TO authenticated;

COMMENT ON TABLE public.member_library_items IS '会员个人书库：想读书目与人生之书当前列表';
COMMENT ON FUNCTION public.list_my_finished_books() IS '从当前用户已读书友圈中聚合已读书目';
COMMENT ON FUNCTION public.admin_export_member_library() IS '管理员导出会员想读书目与人生之书';
