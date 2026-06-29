-- ============================================================
-- 以读攻独 · v23 迁移：消息通知系统
-- 点赞/评论时通知动态作者，铃铛图标+红点+下拉面板
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 通知表
CREATE TABLE IF NOT EXISTS public.notifications (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN ('like', 'comment')),
  actor_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_id     BIGINT NOT NULL REFERENCES public.reading_posts(id) ON DELETE CASCADE,
  is_read     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications(user_id, created_at DESC)
  WHERE is_read = false;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_read_own" ON public.notifications;
CREATE POLICY "notifications_read_own"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
CREATE POLICY "notifications_update_own"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- 2. 更新 toggle_post_like：点赞时写入通知
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

  IF v_post.user_id = v_user_id THEN
    RAISE EXCEPTION 'Cannot like your own post';
  END IF;

  SELECT id INTO v_existing_like
  FROM public.post_likes
  WHERE post_id = p_post_id AND user_id = v_user_id;

  IF FOUND THEN
    DELETE FROM public.post_likes WHERE id = v_existing_like;
    UPDATE public.reading_posts
      SET like_count = GREATEST(like_count - 1, 0), updated_at = now()
      WHERE id = p_post_id;

    UPDATE public.contribution_logs
    SET is_active = false, revoked_at = now()
    WHERE user_id = v_post.user_id
      AND source_type = 'post_like'
      AND source_id = v_existing_like
      AND is_active = true;

    PERFORM public.apply_member_contribution_delta(v_post.user_id, -1);
    v_action := 'unliked';
  ELSE
    INSERT INTO public.post_likes (post_id, user_id)
    VALUES (p_post_id, v_user_id)
    RETURNING id INTO v_existing_like;

    UPDATE public.reading_posts
      SET like_count = like_count + 1, updated_at = now()
      WHERE id = p_post_id;

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

    -- 写入通知
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'like', v_user_id, p_post_id);

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 create_comment：评论时写入通知（不自评）
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

    -- 写入通知
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id);
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. 获取通知列表
CREATE OR REPLACE FUNCTION public.get_notifications(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  id BIGINT,
  type TEXT,
  is_read BOOLEAN,
  created_at TIMESTAMPTZ,
  actor_id UUID,
  actor_name TEXT,
  actor_avatar TEXT,
  post_id BIGINT,
  book_title TEXT
) AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.type,
    n.is_read,
    n.created_at,
    n.actor_id,
    COALESCE(ap.display_name, '书友') AS actor_name,
    ap.avatar_url AS actor_avatar,
    n.post_id,
    rp.book_title
  FROM public.notifications n
  JOIN public.profiles ap ON ap.id = n.actor_id
  JOIN public.reading_posts rp ON rp.id = n.post_id
  WHERE n.user_id = auth.uid()
  ORDER BY n.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 未读数量
CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
RETURNS BIGINT AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM public.notifications
  WHERE user_id = auth.uid() AND is_read = false;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 6. 标记已读
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids BIGINT[])
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE user_id = auth.uid()
    AND id = ANY(p_ids);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 7. 全部已读
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS VOID AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE user_id = auth.uid()
    AND is_read = false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 8. 授权
GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(BIGINT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

-- ============================================================
-- 9. 历史数据补录（部署后执行一次即可）
-- ============================================================

-- 历史点赞 → 通知（跳过给自己的点赞）
INSERT INTO public.notifications (user_id, type, actor_id, post_id, created_at, is_read)
SELECT
  rp.user_id,
  'like',
  pl.user_id,
  pl.post_id,
  pl.created_at,
  true  -- 历史消息默认已读
FROM public.post_likes pl
JOIN public.reading_posts rp ON rp.id = pl.post_id
WHERE rp.user_id <> pl.user_id
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.type = 'like'
      AND n.actor_id = pl.user_id
      AND n.post_id = pl.post_id
      AND n.created_at = pl.created_at
  );

-- 历史评论 → 通知（跳过给自己的评论）
INSERT INTO public.notifications (user_id, type, actor_id, post_id, created_at, is_read)
SELECT
  rp.user_id,
  'comment',
  pc.user_id,
  pc.post_id,
  pc.created_at,
  true  -- 历史消息默认已读
FROM public.post_comments pc
JOIN public.reading_posts rp ON rp.id = pc.post_id
WHERE rp.user_id <> pc.user_id
  AND pc.is_deleted = false
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.type = 'comment'
      AND n.actor_id = pc.user_id
      AND n.post_id = pc.post_id
      AND n.created_at = pc.created_at
  );
