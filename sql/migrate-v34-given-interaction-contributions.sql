-- ============================================================
-- 以读攻独 · v34 迁移：主动互动贡献值
-- 为他人书友圈点赞满 5 次 +1；评论他人书友圈每次 +1。
-- 主动点赞/评论贡献值合计每日最多 10 分。
-- 在 Supabase SQL Editor 中执行
-- ============================================================

-- 统计某个自然日内，主动点赞/评论已经获得的有效贡献值。
-- 日期按 Asia/Shanghai 计算，便于和站内每日规则保持一致。
CREATE OR REPLACE FUNCTION public.given_interaction_points_on_day(
  p_user_id UUID,
  p_created_at TIMESTAMPTZ
)
RETURNS INTEGER AS $$
DECLARE
  v_day_start TIMESTAMPTZ;
  v_day_end TIMESTAMPTZ;
  v_points INTEGER := 0;
BEGIN
  IF p_user_id IS NULL OR p_created_at IS NULL THEN
    RETURN 0;
  END IF;

  v_day_start := (timezone('Asia/Shanghai', p_created_at)::date AT TIME ZONE 'Asia/Shanghai');
  v_day_end := v_day_start + interval '1 day';

  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_points
  FROM public.contribution_logs
  WHERE user_id = p_user_id
    AND source_type IN ('post_like_given_batch', 'post_comment_given')
    AND reason IN ('given_5_likes', 'given_comment')
    AND contribution_scope = 'reading_activity'
    AND is_active = true
    AND created_at >= v_day_start
    AND created_at < v_day_end;

  RETURN COALESCE(v_points, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 尝试写入 1 分主动互动贡献值；若当日已达 10 分或该来源已计分，则不写入。
CREATE OR REPLACE FUNCTION public.try_insert_given_interaction_contribution(
  p_user_id UUID,
  p_source_type TEXT,
  p_source_id BIGINT,
  p_reason TEXT,
  p_created_at TIMESTAMPTZ DEFAULT now()
)
RETURNS BOOLEAN AS $$
BEGIN
  IF p_user_id IS NULL OR p_source_type IS NULL OR p_source_id IS NULL OR p_reason IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contribution_logs
    WHERE user_id = p_user_id
      AND source_type = p_source_type
      AND source_id = p_source_id
      AND reason = p_reason
      AND contribution_scope = 'reading_activity'
      AND is_active = true
  ) THEN
    RETURN false;
  END IF;

  IF public.given_interaction_points_on_day(p_user_id, p_created_at) >= 10 THEN
    RETURN false;
  END IF;

  INSERT INTO public.contribution_logs
    (user_id, source_type, source_id, points, reason, contribution_scope, created_at)
  VALUES
    (p_user_id, p_source_type, p_source_id, 1, p_reason, 'reading_activity', p_created_at);

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 为他人点赞：按当前有效点赞数每满 5 次发放 1 分。
-- 取消点赞后若不再满足对应档位，会回收失效档位的贡献值。
CREATE OR REPLACE FUNCTION public.refresh_given_like_contributions(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_revoked_points INTEGER := 0;
  v_inserted_points INTEGER := 0;
  v_batch RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- 失效的点赞档位：当前有效点赞序列中不再处于第 5/10/15... 个位置的流水。
  WITH valid_batches AS (
    SELECT id
    FROM (
      SELECT
        pl.id,
        row_number() OVER (ORDER BY pl.created_at ASC, pl.id ASC) AS rn
      FROM public.post_likes pl
      JOIN public.reading_posts rp ON rp.id = pl.post_id
      WHERE pl.user_id = p_user_id
        AND rp.user_id <> p_user_id
        AND rp.is_deleted = false
    ) ranked
    WHERE ranked.rn % 5 = 0
  ),
  to_revoke AS (
    SELECT cl.id, cl.points
    FROM public.contribution_logs cl
    WHERE cl.user_id = p_user_id
      AND cl.source_type = 'post_like_given_batch'
      AND cl.reason = 'given_5_likes'
      AND cl.contribution_scope = 'reading_activity'
      AND cl.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM valid_batches vb
        WHERE vb.id = cl.source_id
      )
  ),
  revoked AS (
    UPDATE public.contribution_logs cl
    SET is_active = false,
        revoked_at = now()
    FROM to_revoke tr
    WHERE cl.id = tr.id
    RETURNING tr.points
  )
  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_revoked_points
  FROM revoked;

  IF v_revoked_points > 0 THEN
    PERFORM public.apply_member_contribution_delta(p_user_id, -v_revoked_points);
  END IF;

  FOR v_batch IN
    SELECT id, created_at
    FROM (
      SELECT
        pl.id,
        pl.created_at,
        row_number() OVER (ORDER BY pl.created_at ASC, pl.id ASC) AS rn
      FROM public.post_likes pl
      JOIN public.reading_posts rp ON rp.id = pl.post_id
      WHERE pl.user_id = p_user_id
        AND rp.user_id <> p_user_id
        AND rp.is_deleted = false
    ) ranked
    WHERE ranked.rn % 5 = 0
    ORDER BY created_at ASC, id ASC
  LOOP
    IF public.try_insert_given_interaction_contribution(
      p_user_id,
      'post_like_given_batch',
      v_batch.id,
      'given_5_likes',
      v_batch.created_at
    ) THEN
      v_inserted_points := v_inserted_points + 1;
    END IF;
  END LOOP;

  IF v_inserted_points > 0 THEN
    PERFORM public.apply_member_contribution_delta(p_user_id, v_inserted_points);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.sync_given_like_contributions()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.refresh_given_like_contributions(NEW.user_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM public.refresh_given_like_contributions(OLD.user_id);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_given_like_contributions ON public.post_likes;
CREATE TRIGGER trg_sync_given_like_contributions
  AFTER INSERT OR DELETE ON public.post_likes
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_given_like_contributions();

-- 评论他人书友圈：每条有效评论 +1。
-- 删除评论后回收该条评论带来的主动评论贡献值。
CREATE OR REPLACE FUNCTION public.award_given_comment_contribution(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_commenter_id UUID;
  v_post_owner_id UUID;
  v_comment_created_at TIMESTAMPTZ;
BEGIN
  SELECT pc.user_id, rp.user_id, pc.created_at
    INTO v_commenter_id, v_post_owner_id, v_comment_created_at
  FROM public.post_comments pc
  JOIN public.reading_posts rp ON rp.id = pc.post_id
  WHERE pc.id = p_comment_id
    AND pc.is_deleted = false
    AND rp.is_deleted = false;

  IF v_commenter_id IS NULL OR v_post_owner_id IS NULL OR v_commenter_id = v_post_owner_id THEN
    RETURN;
  END IF;

  IF public.try_insert_given_interaction_contribution(
    v_commenter_id,
    'post_comment_given',
    p_comment_id,
    'given_comment',
    v_comment_created_at
  ) THEN
    PERFORM public.apply_member_contribution_delta(v_commenter_id, 1);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.revoke_given_comment_contribution(p_comment_id BIGINT)
RETURNS VOID AS $$
DECLARE
  v_commenter_id UUID;
  v_points INTEGER := 0;
BEGIN
  SELECT user_id
    INTO v_commenter_id
  FROM public.post_comments
  WHERE id = p_comment_id;

  IF v_commenter_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(points), 0)::INTEGER
    INTO v_points
  FROM public.contribution_logs
  WHERE user_id = v_commenter_id
    AND source_type = 'post_comment_given'
    AND source_id = p_comment_id
    AND reason = 'given_comment'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  IF v_points <= 0 THEN
    RETURN;
  END IF;

  UPDATE public.contribution_logs
  SET is_active = false,
      revoked_at = now()
  WHERE user_id = v_commenter_id
    AND source_type = 'post_comment_given'
    AND source_id = p_comment_id
    AND reason = 'given_comment'
    AND contribution_scope = 'reading_activity'
    AND is_active = true;

  PERFORM public.apply_member_contribution_delta(v_commenter_id, -v_points);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.sync_given_comment_contributions()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_deleted = false THEN
      PERFORM public.award_given_comment_contribution(NEW.id);
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF COALESCE(OLD.is_deleted, false) IS DISTINCT FROM COALESCE(NEW.is_deleted, false) THEN
      IF NEW.is_deleted = true THEN
        PERFORM public.revoke_given_comment_contribution(NEW.id);
      ELSE
        PERFORM public.award_given_comment_contribution(NEW.id);
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_sync_given_comment_contributions ON public.post_comments;
CREATE TRIGGER trg_sync_given_comment_contributions
  AFTER INSERT OR UPDATE OF is_deleted ON public.post_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_given_comment_contributions();

-- 回算既有数据：
-- 1. 对所有未删除、且评论对象不是自己的评论，按评论发生日期补记主动评论贡献值。
-- 2. 对所有未删除动态下的有效点赞，按每个用户第 5/10/15... 个点赞的发生日期补记主动点赞贡献值。
-- 3. 每日主动互动贡献值上限 10 分，回算时同样生效。
DO $$
DECLARE
  v_event RECORD;
  v_inserted BOOLEAN;
BEGIN
  FOR v_event IN
    WITH valid_like_batches AS (
      SELECT user_id, id AS source_id, created_at
      FROM (
        SELECT
          pl.user_id,
          pl.id,
          pl.created_at,
          row_number() OVER (
            PARTITION BY pl.user_id
            ORDER BY pl.created_at ASC, pl.id ASC
          ) AS rn
        FROM public.post_likes pl
        JOIN public.reading_posts rp ON rp.id = pl.post_id
        WHERE rp.user_id <> pl.user_id
          AND rp.is_deleted = false
      ) ranked
      WHERE ranked.rn % 5 = 0
    ),
    valid_comments AS (
      SELECT pc.user_id, pc.id AS source_id, pc.created_at
      FROM public.post_comments pc
      JOIN public.reading_posts rp ON rp.id = pc.post_id
      WHERE pc.is_deleted = false
        AND rp.is_deleted = false
        AND rp.user_id <> pc.user_id
    )
    SELECT user_id, 'post_like_given_batch'::TEXT AS source_type, source_id, 'given_5_likes'::TEXT AS reason, created_at
    FROM valid_like_batches
    UNION ALL
    SELECT user_id, 'post_comment_given'::TEXT AS source_type, source_id, 'given_comment'::TEXT AS reason, created_at
    FROM valid_comments
    ORDER BY user_id, created_at ASC, source_type, source_id
  LOOP
    v_inserted := public.try_insert_given_interaction_contribution(
      v_event.user_id,
      v_event.source_type,
      v_event.source_id,
      v_event.reason,
      v_event.created_at
    );

    IF v_inserted THEN
      PERFORM public.apply_member_contribution_delta(v_event.user_id, 1);
    END IF;
  END LOOP;
END $$;

-- 回算会按历史日期写 contribution_logs。这里重新校准当前月/周贡献，避免历史分数污染本周活跃榜。
UPDATE public.member_stats ms
SET
  contribution_month = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('month', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  contribution_week = COALESCE(
    (SELECT SUM(cl.points) FROM public.contribution_logs cl
     WHERE cl.user_id = ms.user_id AND cl.is_active = true
       AND cl.contribution_scope = 'reading_activity'
       AND cl.created_at >= date_trunc('week', timezone('Asia/Shanghai', now()))
    ), 0
  ),
  updated_at = now();

REVOKE EXECUTE ON FUNCTION public.given_interaction_points_on_day(UUID, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.try_insert_given_interaction_contribution(UUID, TEXT, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refresh_given_like_contributions(UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_given_like_contributions() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_given_comment_contribution(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_given_comment_contribution(BIGINT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_given_comment_contributions() FROM PUBLIC, anon, authenticated;
