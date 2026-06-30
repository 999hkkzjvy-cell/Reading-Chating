-- ============================================================
-- 以读攻独 · v28 迁移：头像上传存储桶 + 公开资料扩展字段
-- avatars 存储桶 + get_public_member_profile 返回 bio/city/wechat_id
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 1. 创建 avatars 存储桶
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true)
  ON CONFLICT (id) DO NOTHING;

-- 2. avatars 存储桶 RLS 策略
DROP POLICY IF EXISTS "avatars_read_all" ON storage.objects;
CREATE POLICY "avatars_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_insert_own" ON storage.objects;
CREATE POLICY "avatars_insert_own"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "avatars_update_own" ON storage.objects;
CREATE POLICY "avatars_update_own"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND auth.role() = 'authenticated');

-- 3. 更新 get_public_member_profile：追加 bio / city / wechat_id
DROP FUNCTION IF EXISTS public.get_public_member_profile(UUID);

CREATE OR REPLACE FUNCTION public.get_public_member_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  bio TEXT,
  city TEXT,
  wechat_id TEXT,
  level INTEGER,
  tier TEXT,
  title TEXT,
  contribution_total INTEGER,
  contribution_month INTEGER,
  contribution_week INTEGER,
  current_badge_key TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    COALESCE(p.display_name, '书友'),
    p.avatar_url,
    p.bio,
    p.city,
    p.wechat_id,
    COALESCE(ms.level, 0),
    COALESCE(ms.tier, '基础会员'),
    COALESCE(ml.title, ''),
    COALESCE(ms.contribution_total, 0),
    COALESCE(ms.contribution_month, 0),
    COALESCE(ms.contribution_week, 0),
    ms.current_badge_key
  FROM public.profiles p
  LEFT JOIN public.member_stats ms ON ms.user_id = p.id
  LEFT JOIN public.member_levels ml ON ml.level = COALESCE(ms.level, 0)
  WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_public_member_profile(UUID) TO anon, authenticated;
