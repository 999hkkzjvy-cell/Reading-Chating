-- ============================================================
-- migrate-v48-badge-cache-busting.sql
-- 让公开主页徽章 RPC 返回 badge_catalog.updated_at，前端用它作为图片缓存版本。
-- ============================================================

DROP FUNCTION IF EXISTS public.list_public_member_display_badges(UUID);

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
  catalog_updated_at TIMESTAMPTZ,
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
      bc.updated_at AS catalog_updated_at,
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
      ranked.catalog_updated_at,
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
      ranked.catalog_updated_at,
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
    dr.catalog_updated_at,
    dr.sort_order
  FROM display_rows dr
  ORDER BY dr.sort_order ASC, dr.awarded_at DESC, dr.id DESC
  LIMIT 6;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_public_member_display_badges(UUID) TO authenticated;

COMMENT ON FUNCTION public.list_public_member_display_badges(UUID) IS
  '公开个人主页展示徽章：优先使用用户在个人中心保存的徽章展示偏好；未保存时按旧规则返回最多 6 枚；返回 catalog_updated_at 供图片缓存破除。';

-- 如果刚刚是同名覆盖 Storage 文件，可以手动刷新对应徽章记录的缓存版本：
-- UPDATE public.badge_catalog
-- SET updated_at = now()
-- WHERE badge_key IN ('commemorative_book_4_claimed', 'commemorative_book_4_finished');

-- ============================================================
-- END migrate-v48-badge-cache-busting.sql
-- ============================================================
