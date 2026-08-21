-- ============================================================
-- 以读攻独 · v52 迁移：书友圈标签与扩展搜索
-- 每位用户维护自己的标签候选项；标签随动态保存并支持公开搜索
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.reading_tags (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT reading_tags_name_length CHECK (char_length(name) BETWEEN 1 AND 30),
  CONSTRAINT reading_tags_normalized_name_length CHECK (char_length(normalized_name) BETWEEN 1 AND 30),
  CONSTRAINT reading_tags_user_name_unique UNIQUE (user_id, normalized_name)
);

CREATE TABLE IF NOT EXISTS public.reading_post_tag_links (
  post_id    BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  tag_id     BIGINT NOT NULL REFERENCES public.reading_tags(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_reading_tags_user
  ON public.reading_tags(user_id, updated_at DESC, name);
CREATE INDEX IF NOT EXISTS idx_reading_tags_normalized_name
  ON public.reading_tags(normalized_name);
CREATE INDEX IF NOT EXISTS idx_reading_post_tag_links_tag
  ON public.reading_post_tag_links(tag_id, post_id);

ALTER TABLE public.reading_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reading_post_tag_links ENABLE ROW LEVEL SECURITY;

-- 标签只通过下方 RPC 读取/写入，避免客户端直接伪造他人的 tag_id。
REVOKE ALL ON TABLE public.reading_tags, public.reading_post_tag_links FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.sync_reading_post_tags(
  p_post_id BIGINT,
  p_tags TEXT[] DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_raw TEXT;
  v_name TEXT;
  v_normalized_name TEXT;
  v_tag_id BIGINT;
  v_seen_names TEXT[] := ARRAY[]::TEXT[];
  v_tag_count INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.reading_posts
    WHERE id = p_post_id
      AND user_id = auth.uid()
      AND is_deleted = false
  ) THEN
    RAISE EXCEPTION 'Post not found or access denied';
  END IF;

  DELETE FROM public.reading_post_tag_links
  WHERE post_id = p_post_id;

  IF p_tags IS NULL THEN
    RETURN;
  END IF;

  FOREACH v_raw IN ARRAY p_tags LOOP
    v_name := regexp_replace(trim(COALESCE(v_raw, '')), '^#+', '');
    v_name := trim(v_name);
    IF v_name = '' THEN
      CONTINUE;
    END IF;

    IF char_length(v_name) > 30 THEN
      RAISE EXCEPTION 'Each tag must be 30 characters or fewer';
    END IF;

    v_normalized_name := lower(v_name);
    IF v_normalized_name = ANY(v_seen_names) THEN
      CONTINUE;
    END IF;

    v_seen_names := array_append(v_seen_names, v_normalized_name);
    v_tag_count := v_tag_count + 1;
    IF v_tag_count > 5 THEN
      RAISE EXCEPTION 'A reading post can have at most 5 tags';
    END IF;

    INSERT INTO public.reading_tags (user_id, name, normalized_name)
    VALUES (auth.uid(), v_name, v_normalized_name)
    ON CONFLICT (user_id, normalized_name) DO UPDATE
      SET name = EXCLUDED.name,
          updated_at = now()
    RETURNING id INTO v_tag_id;

    INSERT INTO public.reading_post_tag_links (post_id, tag_id)
    VALUES (p_post_id, v_tag_id)
    ON CONFLICT (post_id, tag_id) DO NOTHING;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL ON FUNCTION public.sync_reading_post_tags(BIGINT, TEXT[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_my_reading_tags()
RETURNS TABLE (
  id           BIGINT,
  name         TEXT,
  usage_count  BIGINT
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rt.id,
    rt.name,
    COUNT(rptl.post_id)::BIGINT AS usage_count
  FROM public.reading_tags rt
  LEFT JOIN public.reading_post_tag_links rptl ON rptl.tag_id = rt.id
  WHERE rt.user_id = auth.uid()
  GROUP BY rt.id, rt.name, rt.updated_at
  ORDER BY COUNT(rptl.post_id) DESC, rt.updated_at DESC, rt.name ASC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 追加 p_tags 参数；旧签名删除后，避免 RPC 命中旧函数。
DROP FUNCTION IF EXISTS public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL,
  p_tags TEXT[] DEFAULT ARRAY[]::TEXT[]
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
  v_douban_url TEXT;
  v_mood_color TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;
  IF p_visibility NOT IN ('public', 'friends', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;
  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  v_douban_url := trim(COALESCE(p_douban_url, ''));
  IF v_douban_url = '' OR v_douban_url !~ '^https?://book\.douban\.com/subject/[0-9]+/?' THEN
    RAISE EXCEPTION 'Valid Douban book URL is required';
  END IF;

  v_mood_color := NULLIF(trim(COALESCE(p_mood_color, '')), '');
  IF v_mood_color IS NOT NULL AND v_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Invalid mood color';
  END IF;
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;

  INSERT INTO public.reading_posts (
    user_id, post_type, book_title, author, douban_url, cover_url,
    excerpt, content, mood_color, visibility, linked_book_id, rating
  ) VALUES (
    auth.uid(), p_post_type, trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    v_douban_url, NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_excerpt, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    v_mood_color, p_visibility, p_linked_book_id, p_rating
  ) RETURNING id INTO v_post_id;

  PERFORM public.sync_reading_post_tags(v_post_id, p_tags);
  PERFORM public.award_reading_post_contributions(v_post_id);
  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP FUNCTION IF EXISTS public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.update_reading_post(
  p_post_id BIGINT,
  p_post_type TEXT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL,
  p_tags TEXT[] DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_old_visibility TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND user_id = auth.uid() AND is_deleted = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found or access denied';
  END IF;

  IF p_post_type IS NOT NULL THEN
    IF p_post_type NOT IN ('want', 'reading', 'finished') THEN
      RAISE EXCEPTION 'Invalid post type';
    END IF;
    UPDATE public.reading_posts SET post_type = p_post_type WHERE id = p_post_id;
  END IF;
  IF p_excerpt IS NOT NULL THEN
    UPDATE public.reading_posts SET excerpt = NULLIF(trim(p_excerpt), '') WHERE id = p_post_id;
  END IF;
  IF p_content IS NOT NULL THEN
    UPDATE public.reading_posts SET content = NULLIF(trim(p_content), '') WHERE id = p_post_id;
  END IF;
  IF p_mood_color IS NOT NULL THEN
    IF p_mood_color != '' AND p_mood_color !~ '^#[0-9A-Fa-f]{6}$' THEN
      RAISE EXCEPTION 'Invalid mood color';
    END IF;
    UPDATE public.reading_posts
    SET mood_color = NULLIF(trim(p_mood_color), '')
    WHERE id = p_post_id;
  END IF;
  IF p_visibility IS NOT NULL THEN
    IF p_visibility NOT IN ('public', 'friends', 'private') THEN
      RAISE EXCEPTION 'Invalid visibility';
    END IF;
    v_old_visibility := v_post.visibility;
    UPDATE public.reading_posts SET visibility = p_visibility WHERE id = p_post_id;
    IF v_old_visibility != p_visibility THEN
      IF p_visibility = 'private' THEN
        PERFORM public.revoke_reading_post_contributions(p_post_id);
      ELSE
        PERFORM public.award_reading_post_contributions(p_post_id);
      END IF;
    END IF;
  END IF;
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;
  UPDATE public.reading_posts SET rating = p_rating WHERE id = p_post_id;

  IF p_tags IS NOT NULL THEN
    PERFORM public.sync_reading_post_tags(p_post_id, p_tags);
  END IF;

  UPDATE public.reading_posts SET updated_at = now() WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT,
  tags TEXT[]
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, ''),
    COALESCE((
      SELECT array_agg(rt.name ORDER BY rptl.created_at, rt.name)
      FROM public.reading_post_tag_links rptl
      JOIN public.reading_tags rt ON rt.id = rptl.tag_id
      WHERE rptl.post_id = rp.id
    ), ARRAY[]::TEXT[])
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope = 'friends' AND (
        (rp.visibility = 'public' OR rp.visibility = 'friends')
        AND EXISTS (
          SELECT 1 FROM public.user_follows uf
          WHERE uf.follower_id = auth.uid() AND uf.following_id = rp.user_id
        )
      ))
      OR (p_scope = 'public' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

DROP FUNCTION IF EXISTS public.search_reading_posts(TEXT);
DROP FUNCTION IF EXISTS public.search_reading_posts(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.search_reading_posts(
  p_query TEXT,
  p_search_type TEXT DEFAULT 'all'
)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT,
  tags TEXT[]
) AS $$
DECLARE
  v_query TEXT := trim(COALESCE(p_query, ''));
  v_like_query TEXT;
  v_search_type TEXT := lower(trim(COALESCE(p_search_type, 'all')));
BEGIN
  PERFORM public.require_authenticated_member();
  IF v_query = '' THEN
    RETURN;
  END IF;
  IF v_search_type NOT IN ('all', 'tag', 'user', 'book') THEN
    RAISE EXCEPTION 'Invalid reading post search type';
  END IF;
  IF v_search_type = 'tag' THEN
    v_query := regexp_replace(v_query, '^#+', '');
    IF v_query = '' THEN
      RETURN;
    END IF;
  END IF;

  -- 将用户输入视为普通文本，避免把 % 和 _ 当作通配符。
  v_like_query := replace(replace(replace(v_query, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, ''),
    COALESCE((
      SELECT array_agg(rt.name ORDER BY rptl.created_at, rt.name)
      FROM public.reading_post_tag_links rptl
      JOIN public.reading_tags rt ON rt.id = rptl.tag_id
      WHERE rptl.post_id = rp.id
    ), ARRAY[]::TEXT[])
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND rp.visibility = 'public'
    AND (
      (
        v_search_type = 'all'
        AND (
          rp.book_title ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
          OR rp.author ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
          OR COALESCE(p.display_name, '') ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
          OR EXISTS (
            SELECT 1
            FROM public.reading_post_tag_links rptl_search
            JOIN public.reading_tags rt_search ON rt_search.id = rptl_search.tag_id
            WHERE rptl_search.post_id = rp.id
              AND rt_search.name ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
          )
        )
      )
      OR (
        v_search_type = 'tag'
        AND EXISTS (
          SELECT 1
          FROM public.reading_post_tag_links rptl_search
          JOIN public.reading_tags rt_search ON rt_search.id = rptl_search.tag_id
          WHERE rptl_search.post_id = rp.id
            AND rt_search.name ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
        )
      )
      OR (
        v_search_type = 'user'
        AND COALESCE(p.display_name, '') ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
      )
      OR (
        v_search_type = 'book'
        AND (
          rp.book_title ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
          OR rp.author ILIKE '%' || v_like_query || '%' ESCAPE E'\\'
        )
      )
    )
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

DROP FUNCTION IF EXISTS public.list_user_public_posts(UUID);

CREATE OR REPLACE FUNCTION public.list_user_public_posts(p_user_id UUID)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT,
  tags TEXT[]
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, ''),
    COALESCE((
      SELECT array_agg(rt.name ORDER BY rptl.created_at, rt.name)
      FROM public.reading_post_tag_links rptl
      JOIN public.reading_tags rt ON rt.id = rptl.tag_id
      WHERE rptl.post_id = rp.id
    ), ARRAY[]::TEXT[])
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.user_id = p_user_id
    AND rp.is_deleted = false
    AND rp.visibility = 'public'
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.list_my_reading_tags() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_reading_posts(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_user_public_posts(UUID) TO authenticated;

COMMENT ON TABLE public.reading_tags IS '每位用户自己的书友圈标签候选项';
COMMENT ON TABLE public.reading_post_tag_links IS '书友圈动态与用户标签的关联';
COMMENT ON FUNCTION public.list_my_reading_tags() IS '返回当前用户创建过的书友圈标签及使用次数';
COMMENT ON FUNCTION public.search_reading_posts(TEXT, TEXT) IS '按书名/作者、标签或发表用户搜索公开书友圈动态';

-- ============================================================
-- END migrate-v52-reading-post-tags.sql
-- ============================================================
