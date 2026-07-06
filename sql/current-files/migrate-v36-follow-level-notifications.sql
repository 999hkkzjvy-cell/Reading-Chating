-- ============================================================
-- 以读攻独 · v36 迁移：关注与升级通知
-- 1. 关注时通知被关注者：「XXX关注了你」
-- 2. 升级获得新等级徽章时通知本人：「恭喜你升级到 Lv.02 冒险者...」
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 扩展通知表：允许非书友圈动态通知。
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('like', 'comment', 'follow', 'level_badge'));

ALTER TABLE public.notifications
  ALTER COLUMN post_id DROP NOT NULL;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS message TEXT,
  ADD COLUMN IF NOT EXISTS link_path TEXT;

UPDATE public.notifications
SET link_path = '/reading-circle?post=' || post_id::TEXT
WHERE link_path IS NULL
  AND post_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_unread_follow_dedupe
  ON public.notifications(user_id, type, actor_id)
  WHERE is_read = false AND type = 'follow';

-- 重新定义通知列表，兼容 follow / level_badge 这类没有 post_id 的通知。
DROP FUNCTION IF EXISTS public.get_notifications(INTEGER);

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
  book_title TEXT,
  message TEXT,
  link_path TEXT
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
    rp.book_title,
    n.message,
    COALESCE(
      n.link_path,
      CASE WHEN n.post_id IS NOT NULL THEN '/reading-circle?post=' || n.post_id::TEXT ELSE NULL END
    ) AS link_path
  FROM public.notifications n
  LEFT JOIN public.profiles ap ON ap.id = n.actor_id
  LEFT JOIN public.reading_posts rp ON rp.id = n.post_id
  WHERE n.user_id = auth.uid()
  ORDER BY n.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- 关注/取关：关注时写入通知，取消关注不删除历史通知。
CREATE OR REPLACE FUNCTION public.toggle_follow(p_following_id UUID)
RETURNS TEXT AS $$
DECLARE
  v_follower_id UUID;
  v_exists BIGINT;
  v_follower_name TEXT;
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

  SELECT id INTO v_exists
  FROM public.user_follows
  WHERE follower_id = v_follower_id AND following_id = p_following_id;

  IF FOUND THEN
    DELETE FROM public.user_follows WHERE id = v_exists;
    RETURN 'unfollowed';
  ELSE
    INSERT INTO public.user_follows (follower_id, following_id)
    VALUES (v_follower_id, p_following_id);

    SELECT COALESCE(NULLIF(trim(display_name), ''), '书友')
      INTO v_follower_name
    FROM public.profiles
    WHERE id = v_follower_id;

    INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path)
    VALUES (
      p_following_id,
      'follow',
      v_follower_id,
      NULL,
      COALESCE(v_follower_name, '书友') || '关注了你',
      '/user/' || v_follower_id::TEXT
    )
    ON CONFLICT (user_id, type, actor_id) WHERE is_read = false AND type = 'follow'
    DO UPDATE SET
      created_at = now(),
      message = EXCLUDED.message,
      link_path = EXCLUDED.link_path;

    RETURN 'followed';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 升级时写入等级徽章通知。
CREATE OR REPLACE FUNCTION public.recalculate_member_level(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total INTEGER;
  v_old_level INTEGER;
  v_new_level INTEGER;
  v_new_tier TEXT;
  v_new_badge_key TEXT;
  v_new_title TEXT;
BEGIN
  PERFORM public.initialize_member_for_user(p_user_id);

  SELECT contribution_total, level
    INTO v_total, v_old_level
  FROM public.member_stats
  WHERE user_id = p_user_id;

  SELECT level, tier, badge_key, title
    INTO v_new_level, v_new_tier, v_new_badge_key, v_new_title
  FROM public.member_levels
  WHERE is_active = true
    AND v_total >= min_contribution
    AND (max_contribution IS NULL OR v_total <= max_contribution)
  ORDER BY level DESC
  LIMIT 1;

  IF v_new_level IS NULL THEN
    v_new_level := 0;
    v_new_tier := '基础会员';
    v_new_badge_key := NULL;
    v_new_title := '';
  END IF;

  UPDATE public.member_stats
  SET level = v_new_level,
      tier = v_new_tier,
      current_badge_key = v_new_badge_key,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- 补齐当前等级及以下应有等级徽章。
  INSERT INTO public.user_badges (user_id, badge_key, badge_type, awarded_reason)
  SELECT p_user_id, ml.badge_key, 'level', 'level_recalculate'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.badge_key IS NOT NULL
  ON CONFLICT (user_id, badge_key) DO UPDATE SET
    revoked_at = NULL,
    awarded_reason = EXCLUDED.awarded_reason;

  -- 只有真正升级时通知；降级、同级重算、Lv.0 不通知。
  IF v_new_level > COALESCE(v_old_level, 0) AND v_new_level > 0 THEN
    INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path)
    VALUES (
      p_user_id,
      'level_badge',
      p_user_id,
      NULL,
      '恭喜你升级到 Lv.' || lpad(v_new_level::TEXT, 2, '0') || ' ' || COALESCE(v_new_title, '') || '，快去个人中心看看你的徽章并点击答题吧！',
      '/member'
    );
  END IF;

  -- 降级或贡献值回收后，回收高于当前等级的成长徽章。
  -- 开创者、纪念徽章、行为徽章不受等级回退影响。
  UPDATE public.user_badges ub
  SET revoked_at = now()
  FROM public.badge_catalog bc
  WHERE ub.user_id = p_user_id
    AND ub.badge_key = bc.badge_key
    AND ub.badge_type = 'level'
    AND bc.badge_type = 'level'
    AND bc.level > v_new_level
    AND ub.revoked_at IS NULL;

  -- 共读兑换券仍按等级奖励每级最多一张。这里补齐缺失记录，
  -- 已使用或已回收的同等级券不会重复创建。
  INSERT INTO public.resource_redemption_tickets (user_id, status, issued_level, issued_reason)
  SELECT p_user_id, 'available', ml.level, 'level_up'
  FROM public.member_levels ml
  WHERE ml.level > 0
    AND ml.level <= v_new_level
    AND ml.reward_redemption_tickets > 0
  ON CONFLICT DO NOTHING;

  IF v_new_level < COALESCE(v_old_level, 0) THEN
    UPDATE public.resource_redemption_tickets
    SET status = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND issued_reason = 'level_up'
      AND status = 'available'
      AND issued_level > v_new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_follow(UUID) TO authenticated;

-- 补推送一遍既有关注关系，便于上线后核验关注通知。
-- 已存在同一关注者的未读关注通知时只刷新时间和文案。
INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path, is_read, created_at)
SELECT
  uf.following_id,
  'follow',
  uf.follower_id,
  NULL,
  COALESCE(NULLIF(trim(p.display_name), ''), '书友') || '关注了你',
  '/user/' || uf.follower_id::TEXT,
  false,
  now()
FROM public.user_follows uf
LEFT JOIN public.profiles p ON p.id = uf.follower_id
ON CONFLICT (user_id, type, actor_id) WHERE is_read = false AND type = 'follow'
DO UPDATE SET
  created_at = now(),
  message = EXCLUDED.message,
  link_path = EXCLUDED.link_path;

-- 补推送一遍当前等级徽章通知，便于上线后核验升级徽章通知样式。
-- 仅补 Lv.1 以上；已有同文案未读通知时不重复插入。
INSERT INTO public.notifications (user_id, type, actor_id, post_id, message, link_path, is_read, created_at)
SELECT
  ms.user_id,
  'level_badge',
  ms.user_id,
  NULL,
  '恭喜你升级到 Lv.' || lpad(ms.level::TEXT, 2, '0') || ' ' || COALESCE(ml.title, '') || '，快去个人中心看看你的徽章并点击答题吧！',
  '/member',
  false,
  now()
FROM public.member_stats ms
JOIN public.member_levels ml ON ml.level = ms.level
WHERE ms.level > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.notifications n
    WHERE n.user_id = ms.user_id
      AND n.type = 'level_badge'
      AND n.is_read = false
      AND n.message = '恭喜你升级到 Lv.' || lpad(ms.level::TEXT, 2, '0') || ' ' || COALESCE(ml.title, '') || '，快去个人中心看看你的徽章并点击答题吧！'
  );

COMMENT ON FUNCTION public.recalculate_member_level(UUID) IS
  '根据贡献值重算会员等级，补齐当前等级应有徽章，升级时发送徽章通知，并回收高于当前等级的成长徽章和未使用升级券';
