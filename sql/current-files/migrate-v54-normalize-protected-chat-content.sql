-- ============================================================
-- v54: normalize legacy JSON-string chat materials and restore safe metadata
-- Run after migrate-v53-security-and-book-content.sql.
-- ============================================================

BEGIN;

-- Older admin code serialized JSONB chat arrays as text. Keep accepting those
-- rows, but convert them to a real JSON array before reading or storing them.
CREATE OR REPLACE FUNCTION private.normalize_book_chat_payload(p_value JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_value JSONB := COALESCE(p_value, '[]'::JSONB);
BEGIN
  IF jsonb_typeof(v_value) = 'string' THEN
    BEGIN
      v_value := (v_value #>> '{}')::JSONB;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid serialized chatsubstance JSON array';
    END;
  END IF;

  IF jsonb_typeof(v_value) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'chatsubstance must be a JSON array';
  END IF;

  RETURN v_value;
END;
$$;
REVOKE ALL ON FUNCTION private.normalize_book_chat_payload(JSONB)
  FROM PUBLIC, anon, authenticated;

-- The private table retained every chat payload; normalize its representation
-- without changing the chat objects themselves. Invalid rows abort this txn.
UPDATE private.book_protected_content
SET chatsubstance = private.normalize_book_chat_payload(chatsubstance),
    updated_at = now()
WHERE jsonb_typeof(chatsubstance) = 'string';

-- Rebuild only the public, redacted topic/speaker/order stubs. Keep the sync
-- trigger off during this deliberate rewrite so it cannot replace private
-- source content with the redacted public version.
DROP TRIGGER IF EXISTS books_sync_protected_content ON public.books;

UPDATE public.books AS b
SET chatsubstance = redacted.value->'chatsubstance'
FROM private.book_protected_content AS protected
CROSS JOIN LATERAL private.redact_book_protected_fields(
  protected.host_notes,
  protected.activities,
  protected.chatsubstance,
  protected.resources
) AS redacted(value)
WHERE b.id = protected.book_id;

-- Keep future writes compatible with any still-cached pre-v54 admin client.
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
      v_content.chatsubstance := private.normalize_book_chat_payload(OLD.chatsubstance);
      v_content.resources := COALESCE(OLD.resources, '{}'::JSONB);
    END IF;

    IF NEW.host_notes IS DISTINCT FROM OLD.host_notes THEN
      v_content.host_notes := NEW.host_notes;
    END IF;
    IF NEW.activities IS DISTINCT FROM OLD.activities THEN
      v_content.activities := COALESCE(NEW.activities, '[]'::JSONB);
    END IF;
    IF NEW.chatsubstance IS DISTINCT FROM OLD.chatsubstance THEN
      v_content.chatsubstance := private.normalize_book_chat_payload(NEW.chatsubstance);
    END IF;
    IF NEW.resources IS DISTINCT FROM OLD.resources THEN
      v_content.resources := COALESCE(NEW.resources, '{}'::JSONB);
    END IF;
  ELSE
    v_content.book_id := NEW.id;
    v_content.host_notes := NEW.host_notes;
    v_content.activities := COALESCE(NEW.activities, '[]'::JSONB);
    v_content.chatsubstance := private.normalize_book_chat_payload(NEW.chatsubstance);
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

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM private.book_protected_content
    WHERE jsonb_typeof(chatsubstance) <> 'array'
  ) THEN
    RAISE EXCEPTION 'v54 verification failed: protected chatsubstance is not normalized';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.books AS b
    JOIN private.book_protected_content AS protected ON protected.book_id = b.id
    CROSS JOIN LATERAL private.redact_book_protected_fields(
      protected.host_notes,
      protected.activities,
      protected.chatsubstance,
      protected.resources
    ) AS redacted(value)
    WHERE b.chatsubstance IS DISTINCT FROM redacted.value->'chatsubstance'
  ) THEN
    RAISE EXCEPTION 'v54 verification failed: public chat metadata was not restored';
  END IF;
END;
$$;

COMMIT;
