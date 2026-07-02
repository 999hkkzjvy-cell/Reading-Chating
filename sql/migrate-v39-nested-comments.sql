-- ============================================================
-- 以读攻独 · v39 迁移：评论嵌套 + 回复通知
-- post_comments 增加 parent_id，支持回复他人评论
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 0. 更新 notifications 类型约束，加入 comment_reply
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('like', 'comment', 'follow', 'level_badge', 'comment_reply'));

-- 1. 添加 parent_id 列
ALTER TABLE public.post_comments
  ADD COLUMN IF NOT EXISTS parent_id BIGINT
  REFERENCES public.post_comments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_post_comments_parent
  ON public.post_comments(parent_id) WHERE parent_id IS NOT NULL;

-- 2. 更新 create_comment 支持 parent_id + 回复通知
DROP FUNCTION IF EXISTS public.create_comment(BIGINT, TEXT);

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

  -- 验证 parent_id 存在且属于同一帖子
  IF p_parent_id IS NOT NULL THEN
    SELECT * INTO v_parent
    FROM public.post_comments
    WHERE id = p_parent_id AND post_id = p_post_id AND is_deleted = false;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Parent comment not found';
    END IF;
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

  INSERT INTO public.post_comments (post_id, user_id, content, parent_id)
  VALUES (p_post_id, v_user_id, trim(p_content), p_parent_id)
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

    -- 通知动态作者
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_post.user_id, 'comment', v_user_id, p_post_id);
  END IF;

  -- 回复通知：告知被回复的人（不是自己、不是动态作者）
  IF p_parent_id IS NOT NULL AND v_parent.user_id <> v_user_id AND v_parent.user_id <> v_post.user_id THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id)
    VALUES (v_parent.user_id, 'comment_reply', v_user_id, p_post_id);
  END IF;

  RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 更新 list_comments 返回 parent_id 和回复的父评论作者名
DROP FUNCTION IF EXISTS public.list_comments(BIGINT);

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
  updated_at TIMESTAMPTZ,
  parent_id BIGINT,
  parent_author_name TEXT
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
    pc.updated_at,
    pc.parent_id,
    pa.display_name AS parent_author_name
  FROM public.post_comments pc
  LEFT JOIN public.profiles p ON p.id = pc.user_id
  LEFT JOIN public.post_comments pp ON pp.id = pc.parent_id
  LEFT JOIN public.profiles pa ON pa.id = pp.user_id
  WHERE pc.post_id = p_post_id
    AND pc.is_deleted = false
  ORDER BY COALESCE(pc.parent_id, pc.id), pc.created_at ASC
  LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 4. 授权
GRANT EXECUTE ON FUNCTION public.create_comment(BIGINT, TEXT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_comments(BIGINT) TO anon, authenticated;
