-- ============================================================
-- 以读攻独 · v27 迁移：共读密码自动生成与管理员明文展示
-- 在 Supabase SQL Editor 中执行
-- ============================================================

ALTER TABLE public.co_reading_passwords
  ADD COLUMN IF NOT EXISTS password_plain TEXT;

CREATE OR REPLACE FUNCTION public.admin_create_co_reading_password(
  p_book_id BIGINT,
  p_password TEXT,
  p_label TEXT DEFAULT '共读密码',
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
  v_id BIGINT;
  v_password TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  v_password := trim(COALESCE(p_password, ''));
  IF char_length(v_password) < 15 THEN
    RAISE EXCEPTION 'Password must be at least 15 characters';
  END IF;

  IF v_password !~ '^[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Password must contain only letters and numbers';
  END IF;

  INSERT INTO public.co_reading_passwords
    (book_id, label, password_hash, password_plain, starts_at, expires_at, created_by)
  VALUES
    (
      p_book_id,
      COALESCE(NULLIF(trim(COALESCE(p_label, '')), ''), '共读密码'),
      crypt(v_password, gen_salt('bf')),
      v_password,
      p_starts_at,
      p_expires_at,
      auth.uid()
    )
  RETURNING id INTO v_id;

  PERFORM public.ensure_commemorative_badges(p_book_id);
  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

COMMENT ON COLUMN public.co_reading_passwords.password_plain IS
  '管理员后台展示用共读密码明文；RLS 限制为管理员可读';

COMMENT ON TABLE public.co_reading_passwords IS
  '按书籍 / 共读期配置的共读密码，hash 用于核销，password_plain 仅管理员后台展示';
