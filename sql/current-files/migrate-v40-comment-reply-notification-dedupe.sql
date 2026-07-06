-- ============================================================
-- 以读攻独 · v40 迁移：修复楼中楼回复通知去重冲突
-- v39 重写 create_comment 时遗漏了 v24 的通知 ON CONFLICT 去重，
-- 导致同一用户对同一动态/评论连续回复时撞
-- idx_notifications_unread_dedupe 唯一索引。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_comment(
  p_post_id BIGINT,
  p_content TEXT,
  p_parent_id BIGINT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_user_id UUID;
  v_post public.reading_posts%ROWTYPE;
  v_parent public.post_comments%ROWTYPE;
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

  IF p_parent_id IS NOT NULL THEN
    SELECT * INTO v_parent
    FROM public.post_comments
    WHERE id = p_parent_id
      AND post_id = p_post_id
      AND is_deleted = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parent comment not found';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.post_comments
    WHERE post_id = p_post_id
      AND user_id = v_user_id
      AND is_deleted = false
      AND COALESCE(parent_id, 0) = COALESCE(p_parent_id, 0)
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

  INSERT INTO public.post_comments (post_id, user_id, content, parent_id)
  VALUES (p_post_id, v_user_id, v_content, p_parent_id)
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

  IF p_parent_id IS NOT NULL
     AND v_parent.user_id <> v_user_id
     AND v_parent.user_id <> v_post.user_id THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_parent.user_id, 'comment_reply', v_user_id, p_post_id)
    ON CONFLICT (user_id, type, actor_id, post_id) WHERE is_read = false
    DO UPDATE SET created_at = now();
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT, BIGINT) TO authenticated;
