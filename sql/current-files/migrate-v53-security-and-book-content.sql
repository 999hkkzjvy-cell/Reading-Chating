-- ============================================================
-- v53: profile role privileges, internal RPC grants, and protected book data
-- Run after migrate-v52-reading-post-tags.sql.
-- ============================================================

BEGIN;

-- Only the public rules and introduction belong in browser-readable config.
-- The table also contains legacy private settings, including API credentials.
DROP POLICY IF EXISTS site_config_read_all ON public.site_config;
DROP POLICY IF EXISTS site_config_read_public ON public.site_config;
CREATE POLICY site_config_read_public
  ON public.site_config
  FOR SELECT
  TO anon, authenticated
  USING (key IN ('group_rules', 'reading_plan_intro'));

-- Profile creation stays in the auth.users trigger. Clients can update only
-- profile fields that members are allowed to edit; role remains server-owned.
REVOKE INSERT, UPDATE ON TABLE public.profiles FROM PUBLIC, anon, authenticated;
REVOKE INSERT (id, display_name, avatar_url, bio, wechat_id, city, role, created_at, updated_at)
  ON TABLE public.profiles FROM PUBLIC, anon, authenticated;
REVOKE UPDATE (id, display_name, avatar_url, bio, wechat_id, city, role, created_at, updated_at)
  ON TABLE public.profiles FROM PUBLIC, anon, authenticated;
GRANT UPDATE (display_name, avatar_url, bio, wechat_id, city, updated_at)
  ON TABLE public.profiles TO authenticated;

-- These routines are implementation helpers called by triggers and other
-- SECURITY DEFINER functions. They are not Data API endpoints.
REVOKE EXECUTE ON FUNCTION public.apply_member_contribution_delta(UUID, INTEGER)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_reading_post_contributions(BIGINT)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_reading_post_contributions(BIGINT)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.recalculate_member_level(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.initialize_member_for_user(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_view_passes_for_user(UUID)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ensure_commemorative_badges(BIGINT)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_finished_commemorative_badge()
  FROM PUBLIC, anon, authenticated;

-- Store links and full reading materials outside the exposed public schema.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.book_protected_content (
  book_id       BIGINT PRIMARY KEY REFERENCES public.books(id) ON DELETE CASCADE,
  host_notes    TEXT,
  activities    JSONB NOT NULL DEFAULT '[]'::JSONB,
  chatsubstance JSONB NOT NULL DEFAULT '[]'::JSONB,
  resources     JSONB NOT NULL DEFAULT '{}'::JSONB,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE private.book_protected_content ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.book_protected_content FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.redact_book_protected_fields(
  p_host_notes TEXT,
  p_activities JSONB,
  p_chatsubstance JSONB,
  p_resources JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_activities JSONB;
  v_chatsubstance JSONB;
  v_resources JSONB := '{}'::JSONB;
  v_section RECORD;
  v_items JSONB;
  v_host_notes TEXT;
BEGIN
  SELECT COALESCE(jsonb_agg(
    (item - 'meeting_link' - 'replay_link' - 'has_meeting_link' - 'has_replay_link')
    || jsonb_build_object(
      'has_meeting_link', COALESCE(NULLIF(item->>'meeting_link', ''), '') <> '',
      'has_replay_link', COALESCE(NULLIF(item->>'replay_link', ''), '') <> ''
    ) ORDER BY ord
  ), '[]'::JSONB)
  INTO v_activities
  FROM jsonb_array_elements(
    CASE WHEN jsonb_typeof(COALESCE(p_activities, '[]'::JSONB)) = 'array'
      THEN COALESCE(p_activities, '[]'::JSONB) ELSE '[]'::JSONB END
  ) WITH ORDINALITY AS rows(item, ord);

  SELECT COALESCE(jsonb_agg(
    (item - 'content' - 'pdf_url' - 'pdfUrl' - 'file_url' - 'has_content' - 'has_pdf_url')
    || jsonb_build_object(
      'has_content', COALESCE(item->>'content', '') <> '',
      'has_pdf_url', COALESCE(item->>'pdf_url', item->>'pdfUrl', item->>'file_url', '') <> ''
    ) ORDER BY ord
  ), '[]'::JSONB)
  INTO v_chatsubstance
  FROM jsonb_array_elements(
    CASE WHEN jsonb_typeof(COALESCE(p_chatsubstance, '[]'::JSONB)) = 'array'
      THEN COALESCE(p_chatsubstance, '[]'::JSONB) ELSE '[]'::JSONB END
  ) WITH ORDINALITY AS rows(item, ord);

  FOR v_section IN
    SELECT key, value
    FROM jsonb_each(CASE WHEN jsonb_typeof(p_resources) = 'object' THEN p_resources ELSE '{}'::JSONB END)
  LOOP
    SELECT COALESCE(jsonb_agg(
      CASE WHEN v_section.key = 'extended_reading' THEN
        jsonb_build_object('locked', true)
      ELSE
        (item - 'url' - 'has_url')
        || jsonb_build_object('has_url', COALESCE(item->>'url', '') <> '')
      END
      ORDER BY ord
    ), '[]'::JSONB)
    INTO v_items
    FROM jsonb_array_elements(
      CASE WHEN jsonb_typeof(v_section.value) = 'array'
        THEN v_section.value ELSE '[]'::JSONB END
    ) WITH ORDINALITY AS rows(item, ord);

    v_resources := v_resources || jsonb_build_object(v_section.key, v_items);
  END LOOP;

  v_host_notes := CASE
    WHEN p_host_notes IS NULL THEN NULL
    WHEN p_host_notes = '' THEN ''
    ELSE left(p_host_notes, greatest(1, ceil(char_length(p_host_notes) * 0.1)::INTEGER))
  END;

  RETURN jsonb_build_object(
    'host_notes', v_host_notes,
    'activities', v_activities,
    'chatsubstance', v_chatsubstance,
    'resources', v_resources
  );
END;
$$;
REVOKE ALL ON FUNCTION private.redact_book_protected_fields(TEXT, JSONB, JSONB, JSONB)
  FROM PUBLIC, anon, authenticated;

-- Move the existing full payload before replacing public columns with safe
-- previews and metadata. The original rows remain recoverable in this table.
INSERT INTO private.book_protected_content
  (book_id, host_notes, activities, chatsubstance, resources)
SELECT id,
       host_notes,
       COALESCE(activities, '[]'::JSONB),
       COALESCE(chatsubstance, '[]'::JSONB),
       COALESCE(resources, '{}'::JSONB)
FROM public.books
ON CONFLICT (book_id) DO NOTHING;

-- Keep an existing protected copy intact if this migration is rerun after the
-- public rows have already been redacted. INSERT ... DO NOTHING is intentional.

-- Prevent the sync trigger from interpreting the deliberate redaction below
-- as an administrator replacing the protected source data.
DROP TRIGGER IF EXISTS books_sync_protected_content ON public.books;
UPDATE public.books AS b
SET host_notes = redacted.value->>'host_notes',
    activities = redacted.value->'activities',
    chatsubstance = redacted.value->'chatsubstance',
    resources = redacted.value->'resources'
FROM private.book_protected_content AS protected
CROSS JOIN LATERAL private.redact_book_protected_fields(
  protected.host_notes,
  protected.activities,
  protected.chatsubstance,
  protected.resources
) AS redacted(value)
WHERE b.id = protected.book_id;

CREATE OR REPLACE FUNCTION private.sync_book_protected_content()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_content private.book_protected_content%ROWTYPE;
  v_redacted JSONB;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    SELECT * INTO v_content
    FROM private.book_protected_content
    WHERE book_id = OLD.id;

    IF NOT FOUND THEN
      v_content.book_id := OLD.id;
      v_content.host_notes := OLD.host_notes;
      v_content.activities := COALESCE(OLD.activities, '[]'::JSONB);
      v_content.chatsubstance := COALESCE(OLD.chatsubstance, '[]'::JSONB);
      v_content.resources := COALESCE(OLD.resources, '{}'::JSONB);
    END IF;

    IF NEW.host_notes IS DISTINCT FROM OLD.host_notes THEN
      v_content.host_notes := NEW.host_notes;
    END IF;
    IF NEW.activities IS DISTINCT FROM OLD.activities THEN
      v_content.activities := COALESCE(NEW.activities, '[]'::JSONB);
    END IF;
    IF NEW.chatsubstance IS DISTINCT FROM OLD.chatsubstance THEN
      v_content.chatsubstance := COALESCE(NEW.chatsubstance, '[]'::JSONB);
    END IF;
    IF NEW.resources IS DISTINCT FROM OLD.resources THEN
      v_content.resources := COALESCE(NEW.resources, '{}'::JSONB);
    END IF;
  ELSE
    v_content.book_id := NEW.id;
    v_content.host_notes := NEW.host_notes;
    v_content.activities := COALESCE(NEW.activities, '[]'::JSONB);
    v_content.chatsubstance := COALESCE(NEW.chatsubstance, '[]'::JSONB);
    v_content.resources := COALESCE(NEW.resources, '{}'::JSONB);
  END IF;

  INSERT INTO private.book_protected_content
    (book_id, host_notes, activities, chatsubstance, resources, updated_at)
  VALUES
    (NEW.id, v_content.host_notes, v_content.activities, v_content.chatsubstance, v_content.resources, now())
  ON CONFLICT (book_id) DO UPDATE SET
    host_notes = EXCLUDED.host_notes,
    activities = EXCLUDED.activities,
    chatsubstance = EXCLUDED.chatsubstance,
    resources = EXCLUDED.resources,
    updated_at = now();

  v_redacted := private.redact_book_protected_fields(
    v_content.host_notes,
    v_content.activities,
    v_content.chatsubstance,
    v_content.resources
  );
  NEW.host_notes := v_redacted->>'host_notes';
  NEW.activities := v_redacted->'activities';
  NEW.chatsubstance := v_redacted->'chatsubstance';
  NEW.resources := v_redacted->'resources';
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.sync_book_protected_content() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER books_sync_protected_content
  BEFORE INSERT OR UPDATE ON public.books
  FOR EACH ROW EXECUTE FUNCTION private.sync_book_protected_content();

CREATE OR REPLACE FUNCTION public.get_book_protected_content(
  p_book_id BIGINT,
  p_section TEXT DEFAULT 'overview',
  p_index INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_is_admin BOOLEAN := COALESCE(public.is_admin(), false);
  v_has_book_access BOOLEAN := false;
  v_temp_keys TEXT[] := ARRAY[]::TEXT[];
  v_content private.book_protected_content%ROWTYPE;
  v_activities JSONB;
  v_resources JSONB;
  v_chat JSONB;
  v_item RECORD;
  v_key TEXT;
  v_url TEXT;
  v_allowed BOOLEAN;
  v_has_url BOOLEAN;
  v_has_content BOOLEAN;
  v_has_pdf BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Login required';
  END IF;
  IF p_section NOT IN ('overview', 'resources', 'chat', 'admin') THEN
    RAISE EXCEPTION 'Invalid content section';
  END IF;

  SELECT * INTO v_content
  FROM private.book_protected_content
  WHERE book_id = p_book_id;
  IF NOT FOUND THEN
    RETURN '{}'::JSONB;
  END IF;

  IF v_is_admin THEN
    v_has_book_access := true;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.resource_access_grants rag
      WHERE rag.user_id = v_user_id
        AND rag.book_id = p_book_id
        AND rag.resource_scope = 'book'
        AND rag.revoked_at IS NULL
    ) INTO v_has_book_access;

    SELECT COALESCE(array_agg(vp.used_resource_key), ARRAY[]::TEXT[])
    INTO v_temp_keys
    FROM public.view_passes vp
    WHERE vp.user_id = v_user_id
      AND vp.status = 'used'
      AND vp.used_resource_key LIKE ('book:' || p_book_id::TEXT || ':%')
      AND vp.temporary_access_expires_at > now();
  END IF;

  IF p_section = 'admin' THEN
    IF NOT v_is_admin THEN
      RAISE EXCEPTION 'admin_required';
    END IF;
    RETURN jsonb_build_object(
      'host_notes', v_content.host_notes,
      'activities', v_content.activities,
      'chatsubstance', v_content.chatsubstance,
      'resources', v_content.resources
    );
  END IF;

  IF p_section = 'overview' THEN
    SELECT COALESCE(jsonb_agg(
      (item - 'meeting_link' - 'replay_link' - 'has_meeting_link' - 'has_replay_link')
      || jsonb_build_object(
        'meeting_link', CASE
          WHEN v_has_book_access OR ('book:' || p_book_id::TEXT || ':activity:' || (ord - 1)::TEXT || ':meeting_link') = ANY(v_temp_keys)
            THEN COALESCE(item->>'meeting_link', '') ELSE '' END,
        'replay_link', CASE
          WHEN v_has_book_access OR ('book:' || p_book_id::TEXT || ':activity:' || (ord - 1)::TEXT || ':replay_link') = ANY(v_temp_keys)
            THEN COALESCE(item->>'replay_link', '') ELSE '' END,
        'has_meeting_link', COALESCE(item->>'meeting_link', '') <> '',
        'has_replay_link', COALESCE(item->>'replay_link', '') <> ''
      ) ORDER BY ord
    ), '[]'::JSONB)
    INTO v_activities
    FROM jsonb_array_elements(COALESCE(v_content.activities, '[]'::JSONB)) WITH ORDINALITY AS rows(item, ord);

    v_key := 'book:' || p_book_id::TEXT || ':host_notes:all:content';
    RETURN jsonb_build_object(
      'host_notes', CASE WHEN v_has_book_access OR v_key = ANY(v_temp_keys) THEN v_content.host_notes ELSE NULL END,
      'activities', v_activities
    );
  END IF;

  IF p_section = 'resources' THEN
    SELECT COALESCE(jsonb_object_agg(section.key, section.items), '{}'::JSONB)
    INTO v_resources
    FROM (
      SELECT source.key,
        COALESCE((
          SELECT jsonb_agg(
            CASE
              WHEN v_has_book_access
                OR (source.key = 'extended_reading' AND ('book:' || p_book_id::TEXT || ':resource_extended_reading:all:list') = ANY(v_temp_keys))
                OR (source.key <> 'extended_reading' AND ('book:' || p_book_id::TEXT || ':resource_' || source.key || ':' || (item_ord - 1)::TEXT || ':url') = ANY(v_temp_keys))
                THEN (item - 'has_url') || jsonb_build_object('has_url', COALESCE(item->>'url', '') <> '')
              WHEN source.key = 'extended_reading'
                THEN jsonb_build_object('locked', true)
              ELSE (item - 'url') || jsonb_build_object('url', '', 'has_url', COALESCE((item->>'has_url')::BOOLEAN, COALESCE(item->>'url', '') <> ''))
            END ORDER BY item_ord
          )
          FROM jsonb_array_elements(CASE WHEN jsonb_typeof(source.value) = 'array' THEN source.value ELSE '[]'::JSONB END)
            WITH ORDINALITY AS items(item, item_ord)
        ), '[]'::JSONB) AS items
      FROM jsonb_each(COALESCE(v_content.resources, '{}'::JSONB)) AS source(key, value)
    ) AS section;
    RETURN jsonb_build_object('resources', v_resources);
  END IF;

  IF p_section = 'chat' THEN
    IF p_index IS NULL OR p_index < 0 THEN
      RAISE EXCEPTION 'Invalid chat index';
    END IF;
    SELECT item INTO v_chat
    FROM jsonb_array_elements(COALESCE(v_content.chatsubstance, '[]'::JSONB)) WITH ORDINALITY AS rows(item, ord)
    ORDER BY CASE
      WHEN item->>'sort_order' ~ '^[+-]?[0-9]*[.]?[0-9]+$' THEN (item->>'sort_order')::NUMERIC
      ELSE NULL
    END NULLS LAST, ord
    OFFSET p_index LIMIT 1;
    IF v_chat IS NULL THEN
      RETURN '{}'::JSONB;
    END IF;
    v_key := 'book:' || p_book_id::TEXT || ':chat:' || p_index::TEXT || ':content';
    v_allowed := v_has_book_access OR v_key = ANY(v_temp_keys);
    v_has_content := COALESCE(v_chat->>'content', '') <> '';
    v_has_pdf := COALESCE(v_chat->>'pdf_url', v_chat->>'pdfUrl', v_chat->>'file_url', '') <> '';
    IF v_allowed THEN
      RETURN jsonb_build_object('chat', v_chat || jsonb_build_object('has_content', v_has_content, 'has_pdf_url', v_has_pdf));
    END IF;
    RETURN jsonb_build_object('chat',
      (v_chat - 'content' - 'pdf_url' - 'pdfUrl' - 'file_url')
      || jsonb_build_object('content', '', 'pdf_url', '', 'has_content', v_has_content, 'has_pdf_url', v_has_pdf)
    );
  END IF;

  RETURN '{}'::JSONB;
END;
$$;
REVOKE ALL ON FUNCTION public.get_book_protected_content(BIGINT, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_book_protected_content(BIGINT, TEXT, INTEGER)
  TO authenticated;

COMMENT ON TABLE private.book_protected_content IS
  'Full book resources and leading notes; never expose this table through the Data API.';

COMMIT;
