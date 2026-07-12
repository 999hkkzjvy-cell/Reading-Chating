-- ============================================================
-- 以读攻独 · v47 迁移：公开个人主页展示徽章与完本文案
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 已有“读完纪念”徽章统一改为“完本纪念”。
UPDATE public.badge_catalog
SET
  title = replace(title, '读完纪念', '完本纪念'),
  updated_at = now()
WHERE title LIKE '%读完纪念%';

-- 2. 后续自动创建共读完本徽章时直接使用“完本纪念”。
CREATE OR REPLACE FUNCTION public.ensure_commemorative_badges(p_book_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_title TEXT;
BEGIN
  SELECT title INTO v_title
  FROM public.books
  WHERE id = p_book_id;

  IF v_title IS NULL THEN
    RAISE EXCEPTION 'Book not found';
  END IF;

  INSERT INTO public.badge_catalog
    (badge_key, badge_type, title, level, image_bucket, image_path, riddle_key)
  VALUES
    ('commemorative_book_' || p_book_id || '_claimed', 'commemorative', '《' || v_title || '》共读纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_claimed'),
    ('commemorative_book_' || p_book_id || '_finished', 'commemorative', '《' || v_title || '》完本纪念', NULL, 'badges', NULL, 'commemorative_book_' || p_book_id || '_finished')
  ON CONFLICT (badge_key) DO UPDATE SET
    title = EXCLUDED.title,
    badge_type = EXCLUDED.badge_type,
    is_active = true,
    updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. 公开个人主页徽章：优先返回用户在“我的徽章”里保存的展示顺序；
--    若用户尚未保存偏好，则保留旧体验：开创者优先，其余按获得时间倒序取 6 枚。
CREATE OR REPLACE FUNCTION public.list_public_member_display_badges(p_user_id UUID)
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  badge_key TEXT,
  badge_type TEXT,
  awarded_reason TEXT,
  awarded_at TIMESTAMPTZ,
  catalog_badge_type TEXT,
  title TEXT,
  level INTEGER,
  image_bucket TEXT,
  image_path TEXT,
  back_image_bucket TEXT,
  back_image_path TEXT,
  sort_order INTEGER
) AS $$
BEGIN
  PERFORM public.require_authenticated_member();

  RETURN QUERY
  WITH active_badges AS (
    SELECT
      ub.id,
      ub.user_id,
      ub.badge_key,
      ub.badge_type,
      ub.awarded_reason,
      ub.awarded_at,
      bc.badge_type AS catalog_badge_type,
      replace(COALESCE(bc.title, ub.badge_key), '读完纪念', '完本纪念') AS title,
      bc.level,
      bc.image_bucket,
      bc.image_path,
      bc.back_image_bucket,
      bc.back_image_path,
      (
        ub.badge_key = 'founder'
        OR ub.badge_type = 'founder'
        OR bc.badge_type = 'founder'
      ) AS is_founder
    FROM public.user_badges ub
    JOIN public.badge_catalog bc ON bc.badge_key = ub.badge_key
    WHERE ub.user_id = p_user_id
      AND ub.revoked_at IS NULL
  ),
  prefs AS (
    SELECT p.badge_key, p.sort_order
    FROM public.member_badge_display_preferences p
    JOIN active_badges ab ON ab.badge_key = p.badge_key
    WHERE p.user_id = p_user_id
  ),
  has_prefs AS (
    SELECT EXISTS (SELECT 1 FROM prefs) AS value
  ),
  selected_keys AS (
    SELECT prefs.badge_key FROM prefs
    UNION
    SELECT ab.badge_key
    FROM active_badges ab
    WHERE ab.is_founder
      AND NOT EXISTS (
        SELECT 1
        FROM prefs p
        WHERE p.badge_key = ab.badge_key
      )
  ),
  preferred AS (
    SELECT ab.*, p.sort_order
    FROM active_badges ab
    JOIN prefs p ON p.badge_key = ab.badge_key
  ),
  founder AS (
    SELECT ab.*, 0 AS sort_order
    FROM active_badges ab
    CROSS JOIN has_prefs hp
    WHERE hp.value
      AND ab.is_founder
      AND NOT EXISTS (
        SELECT 1
        FROM prefs p
        WHERE p.badge_key = ab.badge_key
      )
  ),
  filler AS (
    SELECT
      ranked.id,
      ranked.user_id,
      ranked.badge_key,
      ranked.badge_type,
      ranked.awarded_reason,
      ranked.awarded_at,
      ranked.catalog_badge_type,
      ranked.title,
      ranked.level,
      ranked.image_bucket,
      ranked.image_path,
      ranked.back_image_bucket,
      ranked.back_image_path,
      ranked.is_founder,
      (100 + ranked.fill_order)::INTEGER AS sort_order
    FROM (
      SELECT
        ab.*,
        (ROW_NUMBER() OVER (ORDER BY ab.is_founder DESC, ab.awarded_at DESC, ab.id DESC))::INTEGER AS fill_order
      FROM active_badges ab
      CROSS JOIN has_prefs hp
      WHERE hp.value
        AND NOT EXISTS (
          SELECT 1
          FROM selected_keys sk
          WHERE sk.badge_key = ab.badge_key
        )
    ) ranked
  ),
  fallback AS (
    SELECT
      ranked.id,
      ranked.user_id,
      ranked.badge_key,
      ranked.badge_type,
      ranked.awarded_reason,
      ranked.awarded_at,
      ranked.catalog_badge_type,
      ranked.title,
      ranked.level,
      ranked.image_bucket,
      ranked.image_path,
      ranked.back_image_bucket,
      ranked.back_image_path,
      ranked.is_founder,
      ranked.fallback_order AS sort_order
    FROM (
      SELECT
        ab.*,
        (ROW_NUMBER() OVER (ORDER BY ab.is_founder DESC, ab.awarded_at DESC, ab.id DESC))::INTEGER AS fallback_order
      FROM active_badges ab
      CROSS JOIN has_prefs hp
      WHERE NOT hp.value
    ) ranked
  ),
  display_rows AS (
    SELECT * FROM preferred
    UNION ALL
    SELECT * FROM founder
    UNION ALL
    SELECT * FROM filler
    UNION ALL
    SELECT * FROM fallback
  )
  SELECT
    dr.id,
    dr.user_id,
    dr.badge_key,
    dr.badge_type,
    dr.awarded_reason,
    dr.awarded_at,
    dr.catalog_badge_type,
    dr.title,
    dr.level,
    dr.image_bucket,
    dr.image_path,
    dr.back_image_bucket,
    dr.back_image_path,
    dr.sort_order
  FROM display_rows dr
  ORDER BY dr.sort_order ASC, dr.awarded_at DESC, dr.id DESC
  LIMIT 6;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) TO authenticated;

COMMENT ON FUNCTION public.list_public_member_display_badges(UUID) IS
  '公开个人主页展示徽章：优先使用用户在个人中心保存的徽章展示偏好；未保存时按旧规则返回最多 6 枚。';

-- ============================================================
-- END migrate-v47-public-display-badges.sql
-- ============================================================
