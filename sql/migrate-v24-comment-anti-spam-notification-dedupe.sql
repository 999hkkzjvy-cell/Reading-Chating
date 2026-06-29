-- ============================================================
-- 以读攻独 · v24 迁移：评论防刷、通知去重
-- 评论 800 字上限；同一用户同一动态 10 分钟内禁止重复评论；
-- 点赞/评论通知按未读维度去重，避免通知列表被刷屏。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 通知去重索引：同一接收者、同一类型、同一触发者、同一动态，只保留一条未读通知
-- 如果已存在重复未读通知，先把较旧的重复项标为已读，保留最新的一条未读。
WITH ranked_unread AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY user_id, type, actor_id, post_id
      ORDER BY created_at DESC, id DESC
    ) AS rn
  FROM public.notifications
  WHERE is_read = false
)
UPDATE public.notifications n
SET is_read = true
FROM ranked_unread r
WHERE n.id = r.id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unread_dedupe
  ON public.notifications(user_id, type, actor_id, post_id)
  WHERE is_read = false;

-- 2. 更新 toggle_post_like：点赞通知未读去重
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

    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'like', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();

    v_action := 'liked';
  END IF;

  RETURN v_action;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 create_comment：800 字上限、重复评论防刷、评论通知未读去重
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
  v_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  v_content := trim(COALESCE(p_content, ''));
  IF v_content = '' THEN
    RAISE EXCEPTION 'Comment content is required';
  END IF;

  IF char_length(v_content) > 800 THEN
    RAISE EXCEPTION 'Comment content exceeds 800 characters';
  END IF;

  SELECT * INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.post_comments
    WHERE post_id = p_post_id
      AND user_id = v_user_id
      AND is_deleted = false
      AND content = v_content
      AND created_at >= now() - interval '10 minutes'
  ) THEN
    RAISE EXCEPTION 'Duplicate comment too soon';
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
  VALUES (p_post_id, v_user_id, v_content)
  RETURNING id INTO v_comment_id;

  UPDATE public.reading_posts
    SET comment_count = comment_count + 1, updated_at = now()
    WHERE id = p_post_id;

  IF v_post.user_id <> v_user_id THEN
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

    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.toggle_post_like(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT) TO authenticated;
