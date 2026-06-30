-- ============================================================
-- 以读攻独 · v29 迁移：好友系统 + 搜索 + 好友可见
-- user_follows 表 + 关注/取关 + 好友可见 + 搜索书友圈
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. user_follows 表
CREATE TABLE IF NOT EXISTS public.user_follows (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  follower_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_user_follows_follower ON public.user_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_following ON public.user_follows(following_id);

ALTER TABLE public.user_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_follows_read_all" ON public.user_follows;
CREATE POLICY "user_follows_read_all"
  ON public.user_follows FOR SELECT USING (true);

DROP POLICY IF EXISTS "user_follows_insert_own" ON public.user_follows;
CREATE POLICY "user_follows_insert_own"
  ON public.user_follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS "user_follows_delete_own" ON public.user_follows;
CREATE POLICY "user_follows_delete_own"
  ON public.user_follows FOR DELETE
  USING (auth.uid() = follower_id);

-- 2. toggle_follow — 关注/取关
CREATE OR REPLACE FUNCTION public.toggle_follow(p_following_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_follower_id UUID;
  v_exists BIGINT;
BEGIN
  v_follower_id := auth.uid();
  IF v_follower_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF v_follower_id = p_following_id THEN
    RAISE EXCEPTION 'Cannot follow yourself';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_following_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  SELECT id INTO v_exists FROM public.user_follows
  WHERE follower_id = v_follower_id AND following_id = p_following_id;

  IF FOUND THEN
    DELETE FROM public.user_follows WHERE id = v_exists;
    RETURN 'unfollowed';
  ELSE
    INSERT INTO public.user_follows (follower_id, following_id)
    VALUES (v_follower_id, p_following_id);
    RETURN 'followed';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 关注/粉丝计数
CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user_id UUID)
RETURNS TABLE (following_count BIGINT, follower_count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM public.user_follows WHERE follower_id = p_user_id),
    (SELECT COUNT(*) FROM public.user_follows WHERE following_id = p_user_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 4. 检查是否已关注
CREATE OR REPLACE FUNCTION public.is_following(p_following_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.user_follows
    WHERE follower_id = auth.uid() AND following_id = p_following_id
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 5. 更新 reading_posts visibility CHECK 支持 friends
ALTER TABLE public.reading_posts
  DROP CONSTRAINT IF EXISTS reading_posts_visibility_check;
ALTER TABLE public.reading_posts
  ADD CONSTRAINT reading_posts_visibility_check
  CHECK (visibility IN ('public', 'friends', 'private'));

-- 6. 更新 create_reading_post 接受 friends
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
  p_rating NUMERIC DEFAULT NULL
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

  PERFORM public.award_reading_post_contributions(v_post_id);
  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 7. 更新 update_reading_post 接受 friends
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
  SELECT * INTO v_post FROM public.reading_posts
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
    UPDATE public.reading_posts SET mood_color = NULLIF(trim(p_mood_color), '') WHERE id = p_post_id;
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
  UPDATE public.reading_posts SET updated_at = now() WHERE id = p_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 8. 更新 list_reading_posts 支持 friends 范围
DROP FUNCTION IF EXISTS public.list_reading_posts(TEXT);

CREATE OR REPLACE FUNCTION public.list_reading_posts(p_scope TEXT DEFAULT 'public')
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  IF p_scope IN ('mine', 'friends') AND auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;

  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND (
      (p_scope = 'mine' AND rp.user_id = auth.uid())
      OR (p_scope = 'friends' AND (
        (rp.visibility = 'public' OR rp.visibility = 'friends')
        AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = rp.user_id)
      ))
      OR (p_scope = 'public' AND rp.visibility = 'public')
    )
  ORDER BY rp.created_at DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 9. 搜索书友圈
CREATE OR REPLACE FUNCTION public.search_reading_posts(p_query TEXT)
RETURNS TABLE (
  id BIGINT, user_id UUID, display_name TEXT, avatar_url TEXT,
  post_type TEXT, book_title TEXT, author TEXT, douban_url TEXT,
  cover_url TEXT, linked_book_id BIGINT, excerpt TEXT, content TEXT,
  mood_color TEXT, visibility TEXT, like_count INTEGER, comment_count INTEGER,
  is_featured BOOLEAN, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ,
  rating NUMERIC, has_liked BOOLEAN, member_level INTEGER, member_title TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    rp.id, rp.user_id,
    COALESCE(p.display_name, '书友'), p.avatar_url,
    rp.post_type, rp.book_title, rp.author, rp.douban_url,
    rp.cover_url, rp.linked_book_id, rp.excerpt, rp.content,
    rp.mood_color, rp.visibility, rp.like_count, rp.comment_count,
    rp.is_featured, rp.created_at, rp.updated_at, rp.rating,
    EXISTS (SELECT 1 FROM public.post_likes pl WHERE pl.post_id = rp.id AND pl.user_id = auth.uid()),
    COALESCE(ms.level, 0), COALESCE(ml.title, '')
  FROM public.reading_posts rp
  LEFT JOIN public.profiles p ON p.id = rp.user_id
  LEFT JOIN public.member_stats ms ON ms.user_id = rp.user_id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE rp.is_deleted = false
    AND rp.visibility = 'public'
    AND (
      rp.book_title ILIKE '%' || p_query || '%'
      OR rp.author ILIKE '%' || p_query || '%'
    )
  ORDER BY rp.created_at DESC
  LIMIT 50;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 10. 授权
GRANT EXECUTE ON FUNCTION public.toggle_follow(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_follow_counts(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_following(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_reading_post(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_reading_post(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_reading_posts(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_reading_posts(TEXT) TO anon, authenticated;
