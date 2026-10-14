-- ============================================================
-- v55: Founder badge unlocks protected book content as the access summary says.
-- Run after migrate-v54-normalize-protected-chat-content.sql.
-- Only the resource entitlement changes; the admin section remains admin-only.
-- ============================================================

BEGIN;

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
  v_is_founder BOOLEAN := COALESCE(public.has_founder_badge(auth.uid()), false);
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

  IF v_is_admin OR v_is_founder THEN
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

COMMIT;
