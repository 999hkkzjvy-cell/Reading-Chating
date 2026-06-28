-- ============================================================
-- 以读攻独 · v13 迁移：书友圈与阅读动态贡献值
-- 公开 / 私密阅读动态、贡献值流水、发布计分和删除 / 改私密回收
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE TABLE IF NOT EXISTS public.contribution_logs (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id             UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  source_type         TEXT NOT NULL,
  source_id           BIGINT,
  points              INTEGER NOT NULL,
  reason              TEXT NOT NULL,
  contribution_scope  TEXT NOT NULL DEFAULT 'reading_activity'
                      CHECK (contribution_scope IN ('reading_activity', 'system_reward', 'admin_adjustment')),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  revoked_at          TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contribution_logs_user_active
  ON public.contribution_logs(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_contribution_logs_source
  ON public.contribution_logs(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_contribution_logs_scope_active
  ON public.contribution_logs(contribution_scope, is_active);

ALTER TABLE public.contribution_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contribution_logs_read_self_or_admin" ON public.contribution_logs;
CREATE POLICY "contribution_logs_read_self_or_admin"
  ON public.contribution_logs
  FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "contribution_logs_admin_write" ON public.contribution_logs;
CREATE POLICY "contribution_logs_admin_write"
  ON public.contribution_logs
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.reading_posts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_type       TEXT NOT NULL CHECK (post_type IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review')),
  book_title      TEXT NOT NULL,
  author          TEXT,
  douban_url      TEXT,
  cover_url       TEXT,
  linked_book_id  BIGINT REFERENCES public.books(id) ON DELETE SET NULL,
  content         TEXT,
  visibility      TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private')),
  like_count      INTEGER NOT NULL DEFAULT 0 CHECK (like_count >= 0),
  comment_count   INTEGER NOT NULL DEFAULT 0 CHECK (comment_count >= 0),
  is_featured     BOOLEAN NOT NULL DEFAULT false,
  is_deleted      BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reading_posts_public
  ON public.reading_posts(created_at DESC)
  WHERE visibility = 'public' AND is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_reading_posts_user
  ON public.reading_posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reading_posts_type
  ON public.reading_posts(post_type);

ALTER TABLE public.reading_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reading_posts_read_public_self_or_admin" ON public.reading_posts;
CREATE POLICY "reading_posts_read_public_self_or_admin"
  ON public.reading_posts
  FOR SELECT
  USING (
    (visibility = 'public' AND is_deleted = false)
    OR auth.uid() = user_id
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "reading_posts_admin_write" ON public.reading_posts;
CREATE POLICY "reading_posts_admin_write"
  ON public.reading_posts
  FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.apply_member_contribution_delta(
  p_user_id UUID,
  p_delta INTEGER
)
RETURNS VOID AS $$
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  UPDATE public.member_stats
  SET contribution_total = GREATEST(contribution_total + p_delta, 0),
      contribution_month = GREATEST(contribution_month + p_delta, 0),
      contribution_week = GREATEST(contribution_week + p_delta, 0),
      updated_at = now()
  WHERE user_id = p_user_id;

  PERFORM public.recalculate_member_level(p_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.award_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_today_count INTEGER;
  v_delta INTEGER := 0;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF NOT FOUND OR v_post.is_deleted OR v_post.visibility <> 'public' THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND is_active = true
  ) THEN
    RETURN;
  END IF;

  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_count
  FROM public.contribution_logs
  WHERE user_id = v_post.user_id
    AND source_type = 'reading_post'
    AND reason = 'post_publish'
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_count >= 3 THEN
    RETURN;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope)
  VALUES
    (v_post.user_id, 'reading_post', p_post_id, 1, 'post_publish', 'reading_activity');
  v_delta := v_delta + 1;

  IF char_length(COALESCE(v_post.content, '')) >= 50 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 2, 'post_long_content', 'reading_activity');
    v_delta := v_delta + 2;
  END IF;

  IF v_post.post_type = 'finished' THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 5, 'post_finished_book', 'reading_activity');
    v_delta := v_delta + 5;
  END IF;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.revoke_reading_post_contributions(p_post_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
  v_delta INTEGER;
BEGIN
  SELECT user_id
    INTO v_user_id
  FROM public.reading_posts
  WHERE id = p_post_id;

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(points), 0)
    INTO v_delta
  FROM public.contribution_logs
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  UPDATE public.contribution_logs
  SET is_active = false,
      revoked_at = now()
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF v_delta <> 0 THEN
    PERFORM public.apply_member_contribution_delta(v_user_id, -v_delta);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.create_reading_post(
  p_post_type TEXT,
  p_book_title TEXT,
  p_author TEXT DEFAULT NULL,
  p_douban_url TEXT DEFAULT NULL,
  p_cover_url TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT 'public',
  p_linked_book_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_post_id BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_post_type NOT IN ('want', 'reading', 'finished', 'excerpt', 'reflection', 'review') THEN
    RAISE EXCEPTION 'Invalid post type';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  IF trim(COALESCE(p_book_title, '')) = '' THEN
    RAISE EXCEPTION 'Book title is required';
  END IF;

  INSERT INTO public.reading_posts (
    user_id,
    post_type,
    book_title,
    author,
    douban_url,
    cover_url,
    content,
    visibility,
    linked_book_id
  )
  VALUES (
    auth.uid(),
    p_post_type,
    trim(p_book_title),
    NULLIF(trim(COALESCE(p_author, '')), ''),
    NULLIF(trim(COALESCE(p_douban_url, '')), ''),
    NULLIF(trim(COALESCE(p_cover_url, '')), ''),
    NULLIF(trim(COALESCE(p_content, '')), ''),
    p_visibility,
    p_linked_book_id
  )
  RETURNING id INTO v_post_id;

  PERFORM public.award_reading_post_contributions(v_post_id);

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.update_reading_post_visibility(
  p_post_id BIGINT,
  p_visibility TEXT
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF p_visibility NOT IN ('public', 'private') THEN
    RAISE EXCEPTION 'Invalid visibility';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND user_id = auth.uid()
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF v_post.visibility = p_visibility THEN
    RETURN;
  END IF;

  UPDATE public.reading_posts
  SET visibility = p_visibility,
      updated_at = now()
  WHERE id = p_post_id;

  IF p_visibility = 'private' THEN
    PERFORM public.revoke_reading_post_contributions(p_post_id);
  ELSE
    PERFORM public.award_reading_post_contributions(p_post_id);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.delete_reading_post(p_post_id BIGINT)
RETURNS VOID AS $$
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
    RAISE EXCEPTION 'Post not found';
  END IF;

  UPDATE public.reading_posts
  SET is_deleted = true,
      updated_at = now()
  WHERE id = p_post_id;

  PERFORM public.revoke_reading_post_contributions(p_post_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.set_reading_post_featured(
  p_post_id BIGINT,
  p_featured BOOLEAN
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_existing_featured_points INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF p_featured AND v_post.visibility <> 'public' THEN
    RAISE EXCEPTION 'Only public posts can be featured';
  END IF;

  UPDATE public.reading_posts
  SET is_featured = p_featured,
      updated_at = now()
  WHERE id = p_post_id;

  SELECT COALESCE(SUM(points), 0)
    INTO v_existing_featured_points
  FROM public.contribution_logs
  WHERE source_type = 'reading_post'
    AND source_id = p_post_id
    AND reason = 'post_featured'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF p_featured AND v_existing_featured_points = 0 THEN
    INSERT INTO public.contribution_logs
      (user_id, source_type, source_id, points, reason, contribution_scope)
    VALUES
      (v_post.user_id, 'reading_post', p_post_id, 10, 'post_featured', 'reading_activity');

    PERFORM public.apply_member_contribution_delta(v_post.user_id, 10);
  ELSIF NOT p_featured AND v_existing_featured_points <> 0 THEN
    UPDATE public.contribution_logs
    SET is_active = false,
        revoked_at = now()
    WHERE source_type = 'reading_post'
      AND source_id = p_post_id
      AND reason = 'post_featured'
      AND contribution_scope = 'reading_activity'
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -v_existing_featured_points);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  post_type TEXT,
  book_title TEXT,
  author TEXT,
  douban_url TEXT,
  cover_url TEXT,
  linked_book_id BIGINT,
  content TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  IF p_scope = 'mine' AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id,
    rp.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    rp.post_type,
    rp.book_title,
    rp.author,
    rp.douban_url,
    rp.cover_url,
    rp.linked_book_id,
    rp.content,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope <> 'mine' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_reading_post_visibility(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_reading_post(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_reading_post_featured(BIGINT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;

COMMENT ON TABLE public.contribution_logs IS '贡献值流水：记录阅读动态、系统奖励和管理员调整产生的贡献值';
COMMENT ON TABLE public.reading_posts IS '书友圈阅读动态：想读、在读、已读、摘抄、感想和书评';
