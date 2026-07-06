-- ============================================================
-- 以读攻独 · v18 迁移：书友圈编辑功能
-- 允许作者编辑已发布动态的内容字段
-- 在 Supabase SQL Editor 中执行
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_reading_post(
  p_post_id BIGINT,
  p_post_type TEXT DEFAULT NULL,
  p_excerpt TEXT DEFAULT NULL,
  p_content TEXT DEFAULT NULL,
  p_mood_color TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_rating NUMERIC DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
  v_post public.reading_posts%ROWTYPE;
  v_old_visibility TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  SELECT *
    INTO v_post
  FROM public.reading_posts
  WHERE id = p_post_id
    AND user_id = auth.uid()
    AND is_deleted = false;

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
    IF p_visibility NOT IN ('public', 'private') THEN
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

  -- 评分：传 null 清空，传数值校验后更新
  IF p_rating IS NOT NULL THEN
    IF p_rating < -10 OR p_rating > 10 THEN
      RAISE EXCEPTION 'Rating must be between -10 and 10';
    END IF;
    IF round(p_rating, 2) <> p_rating THEN
      RAISE EXCEPTION 'Rating can have at most 2 decimal places';
    END IF;
  END IF;
  UPDATE public.reading_posts SET rating = p_rating WHERE id = p_post_id;

  UPDATE public.reading_posts SET updated_at = now() WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;
