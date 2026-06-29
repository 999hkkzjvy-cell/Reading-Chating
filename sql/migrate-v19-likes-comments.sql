-- ============================================================
-- 以读攻独 · v19 迁移：点赞、评论与升级奖励完善
-- Phase 4: post_likes + post_comments 表 + RPC 函数
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- ============================================================
-- 1. post_likes 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.post_likes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_likes_post ON public.post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_user ON public.post_likes(user_id, created_at DESC);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_likes_read_all" ON public.post_likes;
CREATE POLICY "post_likes_read_all"
  ON public.post_likes FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "post_likes_insert_own" ON public.post_likes;
CREATE POLICY "post_likes_insert_own"
  ON public.post_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "post_likes_delete_own" ON public.post_likes;
CREATE POLICY "post_likes_delete_own"
  ON public.post_likes FOR DELETE
  USING (auth.uid() = user_id);

-- ============================================================
-- 2. post_comments 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.post_comments (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content     TEXT NOT NULL CHECK (char_length(trim(content)) > 0),
  is_deleted  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post ON public.post_comments(post_id, created_at ASC)
  WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_post_comments_user ON public.post_comments(user_id, created_at DESC);

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_comments_read_all" ON public.post_comments;
CREATE POLICY "post_comments_read_all"
  ON public.post_comments FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "post_comments_insert_own" ON public.post_comments;
CREATE POLICY "post_comments_insert_own"
  ON public.post_comments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "post_comments_update_own" ON public.post_comments;
CREATE POLICY "post_comments_update_own"
  ON public.post_comments FOR UPDATE
  USING (auth.uid() = user_id);

-- ============================================================
-- 3. toggle_post_like — 点赞/取消点赞
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_post_like(p_post_id BIGINT)
RETURNS TEXT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_existing_like BIGINT;
  v_today_like_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
  v_action TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  -- 不能给自己点赞
  IF v_post.user_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot like your own post';
  END IF;

  SELECT id INTO v_existing_like
  FROM public.post_likes
  WHERE post_id = p_post_id AND user_id = v_user_id;

  IF FOUND THEN
    -- 取消点赞
    DELETE FROM public.post_likes WHERE id = v_existing_like;
    UPDATE public.reading_posts
      SET like_count = GREATEST(like_count - 1, 0), updated_at = now()
      WHERE id = p_post_id;

    -- 回收点赞贡献值
    UPDATE public.contribution_logs
    SET is_active = false, revoked_at = now()
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND source_id = v_existing_like
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -1);
    v_action := 'unliked';
  ELSE
    -- 点赞
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (p_post_id, v_user_id)
    RETURNING id INTO v_existing_like;

    UPDATE public.reading_posts
      SET like_count = like_count + 1, updated_at = now()
      WHERE id = p_post_id;

    -- 检查作者今日点赞贡献值上限（每日 10）
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_like_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND reason = 'received_like'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_like_count < 10 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_like', v_existing_like, 1, 'received_like', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 1);
    END IF;

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 4. create_comment — 发表评论
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_comment_id BIGINT;
  v_today_comment_count INTEGER;
  v_today_start TIMESTAMPTZ;
  v_tomorrow_start TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  IF trim(COALESCE(p_content, '')) = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  -- 每天最多 50 条评论（防刷）
  v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
  v_tomorrow_start := v_today_start + interval '1 day';

  SELECT COUNT(*)
    INTO v_today_comment_count
  FROM public.post_comments
  WHERE user_id = v_user_id
    AND is_deleted = false
    AND created_at >= v_today_start
    AND created_at < v_tomorrow_start;

  IF v_today_comment_count >= 50 THEN
    RAISE EXCEPTION 'Daily comment limit reached';
  END IF;

  INSERT INTO public.post_comments (post_id, user_id, content)
  VALUES (p_post_id, v_user_id, trim(p_content))
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  -- 给动态作者发放评论贡献值（每日上限 20，不对自己评论加分）
  IF v_post.user_id <> v_user_id THEN
    v_today_start := (timezone('Asia/Shanghai', now())::date AT TIME ZONE 'Asia/Shanghai');
    v_tomorrow_start := v_today_start + interval '1 day';

    SELECT COUNT(*)
      INTO v_today_comment_count
    FROM public.contribution_logs
    WHERE user_id = v_post.user_id
      AND source_type = 'post_comment'
      AND reason = 'received_comment'
      AND is_active = true
      AND created_at >= v_today_start
      AND created_at < v_tomorrow_start;

    IF v_today_comment_count < 20 THEN
      INSERT INTO public.contribution_logs
        (user_id, source_type, source_id, points, reason, contribution_scope)
      VALUES
        (v_post.user_id, 'post_comment', v_comment_id, 2, 'received_comment', 'reading_activity');
      PERFORM public.apply_member_contribution_delta(v_post.user_id, 2);
    END IF;
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 5. delete_comment — 删除评论（软删除）
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_comment(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_comment public.post_comments%ROWTYPE;
  v_post public.reading_posts%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT * INTO v_comment
  FROM public.post_comments
  WHERE id = p_comment_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Comment not found';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = v_comment.post_id AND is_deleted = false;

  -- 仅评论作者或动态作者可删除
  IF v_comment.user_id <> auth.uid() AND v_post.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.post_comments
  SET is_deleted = true, updated_at = now()
  WHERE id = p_comment_id;

  UPDATE public.reading_posts
    SET comment_count = GREATEST(comment_count - 1, 0), updated_at = now()
    WHERE id = v_comment.post_id;

  -- 回收评论贡献值
  UPDATE public.contribution_logs
  SET is_active = false, revoked_at = now()
  WHERE user_id = v_post.user_id
    AND source_type = 'post_comment'
    AND source_id = p_comment_id
    AND is_active = true;

  IF FOUND THEN
    PERFORM public.apply_member_contribution_delta(v_post.user_id, -2);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 6. list_comments — 获取某条动态的评论列表
-- ============================================================
CREATE OR REPLACE FUNCTION public.list_comments(p_post_id BIGINT)
RETURNS TABLE (
  id BIGINT,
  post_id BIGINT,
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  content TEXT,
  is_deleted BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pc.id,
    pc.post_id,
    pc.user_id,
    COALESCE(p.display_name, '书友') AS display_name,
    p.avatar_url,
    pc.content,
    pc.is_deleted,
    pc.created_at,
    pc.updated_at
  FROM public.post_comments pc
  LEFT JOIN public.profiles p ON p.id = pc.user_id
  WHERE pc.post_id = p_post_id
    AND pc.is_deleted = false
  ORDER BY pc.created_at ASC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================================
-- 7. 更新 list_reading_posts：追加 has_liked 字段
-- ============================================================
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

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
  excerpt TEXT,
  content TEXT,
  mood_color TEXT,
  visibility TEXT,
  like_count INTEGER,
  comment_count INTEGER,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  rating NUMERIC,
  has_liked BOOLEAN
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
    rp.excerpt,
    rp.content,
    rp.mood_color,
    rp.visibility,
    rp.like_count,
    rp.comment_count,
    rp.is_featured,
    rp.created_at,
    rp.updated_at,
    rp.rating,
    EXISTS (
      SELECT 1 FROM public.post_likes pl
      WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()
    ) AS has_liked
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

-- ============================================================
-- 8. 授权
-- ============================================================
GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_comment(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_comments(BIGINT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;
