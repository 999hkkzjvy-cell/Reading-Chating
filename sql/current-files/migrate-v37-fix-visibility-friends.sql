-- ============================================================
-- 以读攻独 · v37 迁移：修复好友可见切换报错
-- update_reading_post_visibility 支持 friends
-- 在 Supabase SQL Editor 中执行
-- ============================================================

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

  IF p_visibility NOT IN ('public', 'friends', 'private') THEN
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

GRANT EXECUTE ON FUNCTION public.update_reading_post_visibility(BIGINT, TEXT) TO authenticated;
