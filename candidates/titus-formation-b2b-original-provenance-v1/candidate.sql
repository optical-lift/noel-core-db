-- Titus B2B first-draft original-response provenance, SOURCE ONLY.
-- Does not modify public.titus_submit_formation_response_self_api_v1:
-- that existing writer already verifies current signed Person on submission.
-- No production migration or new permission is made by this draft.
BEGIN;

-- Nullable for historical rows: do not reconstruct or fabricate past authors.
ALTER TABLE titus.formation_responses
  ADD COLUMN submitted_by_person_entity_id uuid
    REFERENCES reality.entities(id) ON DELETE RESTRICT,
  ADD COLUMN submitted_by_auth_user_id uuid,
  ADD COLUMN submitted_in_session_id uuid,
  ADD COLUMN original_text_sha256 text;

ALTER TABLE titus.formation_responses
  ADD CONSTRAINT formation_response_original_provenance_shape_v1
  CHECK (
    (
      submitted_by_person_entity_id IS NULL
      AND submitted_by_auth_user_id IS NULL
      AND submitted_in_session_id IS NULL
      AND original_text_sha256 IS NULL
    ) OR (
      submitted_by_person_entity_id IS NOT NULL
      AND submitted_by_auth_user_id IS NOT NULL
      AND submitted_in_session_id IS NOT NULL
      AND original_text_sha256 ~ '^[0-9a-f]{64}$'
    )
  );

COMMENT ON COLUMN titus.formation_responses.submitted_by_person_entity_id
  IS 'Original source-captured current Person on new signed submission. NULL on preexisting responses and unauthenticated administrative imports; never backfill from historical teacher_id.';
COMMENT ON COLUMN titus.formation_responses.original_text_sha256
  IS 'Source-generated SHA-256 fingerprint of submitted raw_text at insert; NOT a source-rights, consent or reviewer authorization. NULL for unverified legacy originals.';

CREATE OR REPLACE FUNCTION titus.capture_formation_response_original_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO pg_catalog
AS $function$
DECLARE
  v_person uuid;
  v_user uuid;
  v_session uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'original Formation responses cannot be deleted';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- Original author, source location and raw learner expression stay fixed;
    -- response_status and other non-original review state can still change.
    IF NEW.raw_text IS DISTINCT FROM OLD.raw_text
      OR NEW.formation_unit_id IS DISTINCT FROM OLD.formation_unit_id
      OR NEW.teacher_id IS DISTINCT FROM OLD.teacher_id
      OR NEW.formation_question_id IS DISTINCT FROM OLD.formation_question_id
      OR NEW.submitted_by_person_entity_id IS DISTINCT FROM OLD.submitted_by_person_entity_id
      OR NEW.submitted_by_auth_user_id IS DISTINCT FROM OLD.submitted_by_auth_user_id
      OR NEW.submitted_in_session_id IS DISTINCT FROM OLD.submitted_in_session_id
      OR NEW.original_text_sha256 IS DISTINCT FROM OLD.original_text_sha256
    THEN
      RAISE EXCEPTION 'Formation original source and attribution are immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'unsupported Formation original operation';
  END IF;

  -- Never trust client- or privileged-import-supplied provenance fields.
  NEW.submitted_by_person_entity_id := NULL;
  NEW.submitted_by_auth_user_id := NULL;
  NEW.submitted_in_session_id := NULL;
  NEW.original_text_sha256 := NULL;

  v_person := titus.current_authenticated_person_entity_id_v1();
  v_user := auth.uid();

  BEGIN
    v_session := nullif(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'invalid signed Formation session';
  END;

  -- Administrative imports and old source writers with NO signed actor
  -- are allowed to remain expressly unverified, never forged as a learner.
  IF v_person IS NULL AND v_user IS NULL AND v_session IS NULL THEN
    RETURN NEW;
  END IF;

  -- Partial or unbound identities are never accepted as a signed original.
  IF v_person IS NULL OR v_user IS NULL OR v_session IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM titus.teacher_person_bindings b
      WHERE b.teacher_id = NEW.teacher_id
        AND b.person_entity_id = v_person
        AND b.binding_state = 'active'
        AND b.retired_at IS NULL
    )
  THEN
    RAISE EXCEPTION 'Formation submission lacks a valid signed learner binding';
  END IF;

  NEW.submitted_by_person_entity_id := v_person;
  NEW.submitted_by_auth_user_id := v_user;
  NEW.submitted_in_session_id := v_session;
  NEW.original_text_sha256 :=
      encode(sha256(convert_to(NEW.raw_text,'UTF8')),'hex');

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION titus.capture_formation_response_original_v1()
  FROM PUBLIC;
DO $roles$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.capture_formation_response_original_v1() FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.capture_formation_response_original_v1() FROM authenticated';
  END IF;
END;
$roles$;

CREATE TRIGGER formation_response_original_provenance_v1
BEFORE INSERT OR UPDATE OR DELETE ON titus.formation_responses
FOR EACH ROW EXECUTE FUNCTION titus.capture_formation_response_original_v1();

-- No new public RPC, RLS policy, user grant, feedback write or reviewer read.
-- Existing publication and cross-Person review boundaries remain unchanged.
COMMIT;
