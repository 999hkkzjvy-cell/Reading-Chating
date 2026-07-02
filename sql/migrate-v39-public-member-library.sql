-- ============================================================
-- 以读攻独 · v39 迁移：个人主页公开书库
-- 将会员的已读书目、想读书目、人生之书提供给个人主页展示。
-- 在 Supabase SQL Editor 中执行，需先执行 v38。
-- ============================================================

CREATE OR REPLACE FUNCTION public.list_public_member_library(p_user_id UUID)
RETURNS TABLE (
  list_type TEXT,
  post_id BIGINT,
  sort_order INTEGER,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  note TEXT,
  item_at TIMESTAMPTZ
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH finished AS (
    SELECT
      rp.*,
      COALESCE(NULLIF(trim(rp.douban_url), ''), 'title:' || lower(trim(rp.book_title))) AS book_key
    FROM public.reading_posts rp
    WHERE rp.user_id = p_user_id
      AND rp.post_type = 'finished'
      AND rp.visibility = 'public'
      AND rp.is_deleted = false
  ),
  ranked_finished AS (
    SELECT
      f.*,
      row_number() OVER (PARTITION BY f.book_key ORDER BY f.created_at DESC, f.id DESC) AS rn
    FROM finished f
  )
  SELECT *
  FROM (
    SELECT
      'finished'::TEXT AS list_type,
      rf.id AS post_id,
      NULL::INTEGER AS sort_order,
      rf.book_title,
      rf.author,
      rf.douban_url,
      rf.cover_url,
      rf.content AS note,
      rf.created_at AS item_at
    FROM ranked_finished rf
    WHERE rf.rn = 1

    UNION ALL

    SELECT
      mli.list_type,
      NULL::BIGINT AS post_id,
      mli.sort_order,
      mli.book_title,
      mli.author,
      mli.douban_url,
      mli.cover_url,
      mli.reason AS note,
      mli.updated_at AS item_at
    FROM public.member_library_items mli
    WHERE mli.user_id = p_user_id
      AND mli.list_type IN ('want', 'life')
  ) library
  ORDER BY
    CASE library.list_type
      WHEN 'life' THEN 1
      WHEN 'want' THEN 2
      ELSE 3
    END,
    library.sort_order NULLS LAST,
    library.item_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_public_member_library(UUID) TO authenticated;

COMMENT ON FUNCTION public.list_public_member_library(UUID) IS
  '个人主页展示公开书库：公开已读书目、想读书目、人生之书';
