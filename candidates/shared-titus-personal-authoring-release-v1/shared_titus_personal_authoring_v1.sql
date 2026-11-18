-- PERSONAL TITUS AUTHORING, NONDESTRUCTIVE SOURCE CANDIDATE.
-- Derived from exact held Noel #2617 f9cabf634d0b660f25d6b7244ff7351623aa4c28.
-- REVIEW CANDIDATE ONLY; not a generated migration or authorized release.
-- Transactional release-shaped source; the canonical protected workflow
-- and exact owner approval, not a caller-set clone marker, govern release.
-- Use the same canonical Course identity. Existing Ledger-first rows and
-- existing Titus records are neither adopted nor retired by this tranche.
BEGIN;

DO $guard$
BEGIN
 IF to_regclass('atlas.teaching_courses') IS NULL OR
    to_regprocedure('atlas.guard_teaching_course_activation_v1()') IS NULL OR
    to_regprocedure('atlas.guard_teaching_course_identity_update_v1()') IS NULL OR
    NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.teaching_courses'::regclass
      AND tgname='teaching_courses_activation_guard_v1' AND NOT tgisinternal AND tgenabled='O') OR
    NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.teaching_courses'::regclass
      AND tgname='teaching_courses_identity_immutable_v1' AND NOT tgisinternal AND tgenabled='O')
 THEN RAISE EXCEPTION 'existing Course guards required' USING ERRCODE='42501'; END IF;
END $guard$;

-- Only the new Person-origin shape may omit institutional founding fields.
-- Existing roots retain their exact identifiers, columns, FKs and old guards.
ALTER TABLE atlas.teaching_courses
 ADD COLUMN created_by_person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN create_request_id uuid,
 ADD COLUMN created_by_auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ALTER COLUMN ledger_id DROP NOT NULL,
 ALTER COLUMN capability_activation_id DROP NOT NULL,
 ALTER COLUMN created_by_person_id DROP NOT NULL,
 ALTER COLUMN created_by_principal_id DROP NOT NULL,
 ADD CONSTRAINT teaching_courses_complete_origin_v1 CHECK (
  (created_by_person_entity_id IS NULL AND create_request_id IS NULL
   AND created_by_auth_user_id IS NULL AND ledger_id IS NOT NULL
   AND capability_activation_id IS NOT NULL AND created_by_person_id IS NOT NULL
   AND created_by_principal_id IS NOT NULL)
 OR
  (created_by_person_entity_id IS NOT NULL AND create_request_id IS NOT NULL
   AND created_by_auth_user_id IS NOT NULL AND ledger_id IS NULL
   AND capability_activation_id IS NULL AND created_by_person_id IS NULL
   AND created_by_principal_id IS NULL));
CREATE UNIQUE INDEX teaching_courses_person_request_v1
 ON atlas.teaching_courses(created_by_person_entity_id,create_request_id)
 WHERE created_by_person_entity_id IS NOT NULL;

-- Preserve the exact existing activation guard for every Ledger-origin row.
-- Its own function and the existing identity/updated_at triggers stay intact.
-- The exclusive shape check + additional immutable origin guard prevent
-- changing an existing institutional row into a personal row to evade it.
DROP TRIGGER teaching_courses_activation_guard_v1 ON atlas.teaching_courses;
CREATE TRIGGER teaching_courses_activation_guard_v1
 BEFORE INSERT OR UPDATE ON atlas.teaching_courses FOR EACH ROW
 WHEN (NEW.created_by_person_entity_id IS NULL)
 EXECUTE FUNCTION atlas.guard_teaching_course_activation_v1();

CREATE FUNCTION atlas.guard_person_course_identity_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog
AS $$
BEGIN
 IF old.id IS DISTINCT FROM new.id
 OR old.created_by_person_entity_id IS DISTINCT FROM new.created_by_person_entity_id
 OR old.create_request_id IS DISTINCT FROM new.create_request_id
 OR old.created_by_auth_user_id IS DISTINCT FROM new.created_by_auth_user_id
 OR old.course_key IS DISTINCT FROM new.course_key
 OR old.created_at IS DISTINCT FROM new.created_at
 THEN RAISE EXCEPTION 'Course identity and founding custody are immutable'
  USING ERRCODE='55000';
 END IF;
 IF old.status='retired' AND new.status<>'retired' THEN
  RAISE EXCEPTION 'retired Course identity cannot be reactivated'
  USING ERRCODE='55000';
 END IF;
 RETURN new;
END
$$;
REVOKE ALL ON FUNCTION atlas.guard_person_course_identity_v1() FROM PUBLIC,service_role;
CREATE TRIGGER teaching_courses_person_identity_immutable_v1
 BEFORE UPDATE ON atlas.teaching_courses FOR EACH ROW
 EXECUTE FUNCTION atlas.guard_person_course_identity_v1();

-- No direct client tables: source RPCs with signed Person checks are mandatory.
ALTER TABLE atlas.teaching_courses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_courses FROM PUBLIC,anon,authenticated;

-- These are content/history facets of that SAME original Course.
CREATE TABLE atlas.teaching_course_manuscript_revisions (
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 edit_request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK (based_on_revision>=0),
 revision_number integer NOT NULL CHECK (revision_number=based_on_revision+1),
 body_text text NOT NULL CHECK (char_length(body_text)<=40000),
 recorded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(course_id,edit_request_id),UNIQUE(course_id,revision_number)
);
CREATE TABLE atlas.teaching_course_units (
 unit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 create_request_id uuid NOT NULL,
 kind text NOT NULL CHECK (kind IN ('lesson','assignment')),
 title text NOT NULL CHECK (title=btrim(title) AND length(title) BETWEEN 1 AND 150),
 display_position integer NOT NULL CHECK (display_position>0),
 created_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 created_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(course_id,create_request_id),
 UNIQUE(course_id,display_position)
);
CREATE TABLE atlas.teaching_course_unit_revisions (
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 edit_request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK (based_on_revision>=0),
 revision_number integer NOT NULL CHECK (revision_number=based_on_revision+1),
 body_text text NOT NULL CHECK (char_length(body_text)<=20000),
 recorded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(unit_id,edit_request_id),UNIQUE(unit_id,revision_number)
);
ALTER TABLE atlas.teaching_course_manuscript_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_unit_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_manuscript_revisions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.teaching_course_units FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.teaching_course_unit_revisions FROM PUBLIC,anon,authenticated,service_role;

-- Source identity requires a CURRENT Atlas reality_access session, not just
-- an unexpired signed bearer with an old auth.uid. That source verifies auth
-- session_id, account availability, canonical Reality Person and native Atlas.
-- Independently require EXACTLY ONE current binding; the existing reality
-- resolver's LIMIT 1 must never silently pick a Person when ambiguous.
CREATE FUNCTION atlas.current_person_for_private_course_v1()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $course_person$
DECLARE v_people uuid[]; v_auth uuid; v_access jsonb; v_subject uuid;
BEGIN
 v_auth:=auth.uid();
 IF v_auth IS NULL THEN
  RAISE EXCEPTION 'current signed Person session required' USING ERRCODE='42501';
 END IF;
 v_access:=atlas.reality_access_self_api_v1();
 IF coalesce(v_access->>'state','')<>'ready'
    OR coalesce(v_access->>'authenticated','false')<>'true'
    OR coalesce(v_access->>'contractVersion','')<>'reality_access_self_v1' THEN
  RAISE EXCEPTION 'current Atlas Reality session required' USING ERRCODE='42501';
 END IF;
 BEGIN
  v_subject:=(v_access->'person'->>'id')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN
  RAISE EXCEPTION 'current Reality Person unverified' USING ERRCODE='42501';
 END;
 SELECT array_agg(b.person_entity_id) INTO v_people
 FROM reality.auth_person_bindings b JOIN reality.entities e
   ON e.id=b.person_entity_id
   AND e.entity_kind='person' AND e.identity_state='canonical'
 WHERE b.auth_user_id=v_auth
   AND b.binding_state='active' AND b.retired_at IS NULL;
 IF coalesce(array_length(v_people,1),0)<>1
    OR v_subject IS DISTINCT FROM v_people[1] THEN
  RAISE EXCEPTION 'unique current canonical Person required' USING ERRCODE='42501';
 END IF;
 RETURN v_people[1];
END
$course_person$;
REVOKE ALL ON FUNCTION atlas.current_person_for_private_course_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Titus product access is independent of universal Person-authored Course
-- identity. Preserve the one existing source-issued private-pilot/purchase
-- grant as an actual Person-scoped access original, NOT a Course workspace.
-- Creating a Course through shared source does not convey a Titus license.
CREATE TABLE titus.course_authoring_access_grants (
 person_entity_id uuid PRIMARY KEY REFERENCES reality.entities(id) ON DELETE RESTRICT,
 grant_source_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 grant_kind text NOT NULL CHECK (grant_kind IN ('private_pilot','purchase')),
 grant_source_receipt text NOT NULL UNIQUE
  CHECK (grant_source_receipt=btrim(grant_source_receipt) AND
         length(grant_source_receipt) BETWEEN 8 AND 200),
 state text NOT NULL CHECK (state IN ('active','suspended','revoked')),
 granted_at timestamptz NOT NULL,
 valid_until timestamptz,
 CHECK (valid_until IS NULL OR valid_until>granted_at)
);
ALTER TABLE titus.course_authoring_access_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.course_authoring_access_grants FROM PUBLIC,anon,authenticated,service_role;

-- Held product-access source: a prior authorized pilot/purchase receipt has
-- immutable founding Person, issuer Auth, kind, receipt and issuance time.
-- Founding state and expiry are preserved from the authorized original.
-- Subsequent state changes require separate append-only source receipts.
-- No trusted product grant issuer or transition issuer has been released;
-- never mistake clone-owner inserts for a lawful payment/pilot decision.
CREATE FUNCTION titus.guard_course_authoring_grant_origin_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog
AS $grant_origin$
BEGIN
 IF TG_OP='DELETE' THEN
  RAISE EXCEPTION 'Titus product grant origin cannot be deleted'
   USING ERRCODE='55000';
 END IF;
 IF OLD.person_entity_id IS DISTINCT FROM NEW.person_entity_id
 OR OLD.grant_source_auth_user_id IS DISTINCT FROM NEW.grant_source_auth_user_id
 OR OLD.grant_kind IS DISTINCT FROM NEW.grant_kind
 OR OLD.grant_source_receipt IS DISTINCT FROM NEW.grant_source_receipt
 OR OLD.granted_at IS DISTINCT FROM NEW.granted_at
 OR OLD.state IS DISTINCT FROM NEW.state
 OR OLD.valid_until IS DISTINCT FROM NEW.valid_until THEN
  RAISE EXCEPTION 'Titus product grant origin is immutable'
   USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END
$grant_origin$;
REVOKE ALL ON FUNCTION titus.guard_course_authoring_grant_origin_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER titus_course_authoring_grant_origin_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_access_grants
 FOR EACH ROW EXECUTE FUNCTION titus.guard_course_authoring_grant_origin_v1();

-- Every post-founding status change is a separate immutable source event.
-- Direct authenticated/anon table access is revoked. An authorized issuer
-- and its proof (payment, pilot action, actor jurisdiction) MUST be designed
-- separately; this candidate provides no public transition writer.
CREATE TABLE titus.course_authoring_access_status_events (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 person_entity_id uuid NOT NULL
  REFERENCES titus.course_authoring_access_grants(person_entity_id)
  ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 next_state text NOT NULL CHECK(next_state IN ('active','suspended','revoked')),
 source_evidence_receipt text NOT NULL UNIQUE CHECK(
  source_evidence_receipt=btrim(source_evidence_receipt)
  AND length(source_evidence_receipt) BETWEEN 8 AND 200),
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(person_entity_id,request_id)
);
CREATE INDEX titus_authoring_status_event_latest_v1
 ON titus.course_authoring_access_status_events(person_entity_id,event_seq DESC);
ALTER TABLE titus.course_authoring_access_status_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.course_authoring_access_status_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE titus.course_authoring_access_status_events_event_seq_seq
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION titus.guard_authoring_status_event_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog
AS $status_event$
DECLARE v_state text;
BEGIN
 IF TG_OP <> 'INSERT' THEN
  RAISE EXCEPTION 'Titus product status event cannot be changed or deleted'
   USING ERRCODE='55000';
 END IF;
 -- This row lock serializes simultaneous decisions for the same original.
 SELECT g.state INTO v_state
  FROM titus.course_authoring_access_grants g
  WHERE g.person_entity_id=NEW.person_entity_id FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'known original Titus authoring grant required'
   USING ERRCODE='42501';
 END IF;
 SELECT e.next_state INTO v_state
  FROM titus.course_authoring_access_status_events e
  WHERE e.person_entity_id=NEW.person_entity_id
  ORDER BY e.event_seq DESC LIMIT 1;
 IF NOT FOUND THEN
  SELECT g.state INTO v_state
   FROM titus.course_authoring_access_grants g
   WHERE g.person_entity_id=NEW.person_entity_id;
 END IF;
 IF v_state='revoked' OR v_state=NEW.next_state THEN
  RAISE EXCEPTION 'terminal or unchanged Titus grant status cannot transition'
   USING ERRCODE='23514';
 END IF;
 IF NOT ((v_state='active' AND NEW.next_state IN ('suspended','revoked'))
  OR (v_state='suspended' AND NEW.next_state IN ('active','revoked'))) THEN
  RAISE EXCEPTION 'invalid Titus access status transition' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END
$status_event$;
REVOKE ALL ON FUNCTION titus.guard_authoring_status_event_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER titus_authoring_status_event_immutable_v1
 BEFORE INSERT OR UPDATE OR DELETE ON titus.course_authoring_access_status_events
 FOR EACH ROW EXECUTE FUNCTION titus.guard_authoring_status_event_v1();

-- One shared internal predicate for BOTH source guard and browser projection.
-- Latest immutable event determines current state, while founding expiry still
-- applies. Old Course originals are not removed when an entitlement ends.
CREATE FUNCTION titus.authoring_grant_current_active_v1(p_person uuid)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $effective_access$
 SELECT p_person IS NOT NULL AND EXISTS(
  SELECT 1 FROM titus.course_authoring_access_grants g
  WHERE g.person_entity_id=p_person
   AND g.granted_at<=clock_timestamp()
   AND (g.valid_until IS NULL OR g.valid_until>clock_timestamp())
   AND COALESCE((
     SELECT e.next_state FROM titus.course_authoring_access_status_events e
     WHERE e.person_entity_id=g.person_entity_id
     ORDER BY e.event_seq DESC LIMIT 1
    ),g.state)='active'
 );
$effective_access$;
REVOKE ALL ON FUNCTION titus.authoring_grant_current_active_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Initial personal pilot write membrane: require current Titus access at the
-- database entrypoint, not merely the app. A future Atlas Person-authoring
-- entrypoint will require its own authorized operation on this same root.
CREATE FUNCTION titus.require_authoring_access_v1()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $access$
DECLARE v_person uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 IF NOT titus.authoring_grant_current_active_v1(v_person) THEN
  RAISE EXCEPTION 'current Titus authoring access required'
   USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END
$access$;
REVOKE ALL ON FUNCTION titus.require_authoring_access_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Minimal deliberately exposed Titus product check, without grant receipt
-- or other Person data. A denied grant does not grant Course read access.
CREATE FUNCTION public.titus_authoring_access_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $self_access$
DECLARE v_person uuid; v_eligible boolean;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT titus.authoring_grant_current_active_v1(v_person)
 INTO v_eligible;
 RETURN jsonb_build_object('contractVersion','titus_authoring_access_v1',
  'canUseTitus',v_eligible);
END
$self_access$;
REVOKE ALL ON FUNCTION public.titus_authoring_access_self_api_v1()
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.titus_authoring_access_self_api_v1()
 TO authenticated;

-- First ONE Course root-creation writer. Subsequent institution operation
-- references the same id. No legacy workspace or Principal ID is accepted.
CREATE FUNCTION public.shared_teaching_course_create_self_api_v1(
 p_request_id uuid,p_title text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $$
DECLARE
 v_person uuid;v_auth uuid;v_title text;v_found atlas.teaching_courses%ROWTYPE;v_id uuid;
BEGIN
 v_person:=titus.require_authoring_access_v1();
 v_auth:=auth.uid();
 IF p_request_id IS NULL THEN
  RAISE EXCEPTION 'idempotent request ID required' USING ERRCODE='22023';
 END IF;
 v_title:=btrim(coalesce(p_title,''));
 IF length(v_title) NOT BETWEEN 1 AND 150 THEN
  RAISE EXCEPTION 'valid Course title required' USING ERRCODE='22023';
 END IF;
 -- Serialize source acts by this canonical Person without a Course/Ledger
 -- lock; source permission is not derived from the private Titus workspace.
 PERFORM 1 FROM reality.entities e WHERE e.id=v_person FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'current Person unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_found FROM atlas.teaching_courses
 WHERE created_by_person_entity_id=v_person AND create_request_id=p_request_id;
 IF v_found.id IS NOT NULL THEN
  IF v_found.name IS DISTINCT FROM v_title THEN
   RAISE EXCEPTION 'Course retry changed founding title' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','shared_course_create_self_v1',
   'courseId',v_found.id,'alreadyExists',true);
 END IF;
 v_id:=gen_random_uuid();
 INSERT INTO atlas.teaching_courses(
  id,course_key,name,status,created_by_person_entity_id,
  created_by_auth_user_id,create_request_id)
 VALUES (v_id,v_id::text,v_title,'active',v_person,v_auth,p_request_id);
 RETURN jsonb_build_object('contractVersion','shared_course_create_self_v1',
  'courseId',v_id,'alreadyExists',false);
END
$$;
REVOKE ALL ON FUNCTION public.shared_teaching_course_create_self_api_v1(uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_course_create_self_api_v1(uuid,text)
 TO authenticated;

-- This candidate is deliberately not the full source release. No migration of
-- real founder material, new Unit writers, institutional standing or deletion.
-- The follow-up clone tranche must replace all old writer/readers atomically.
-- End M1 candidate. No transaction is committed by this file.

-- Independent existing authoring operations, same source root.
-- M3 SOURCE CANDIDATE — canonical Person-authored Course readers/writers.
-- Apply ONLY in a disposable PG17 test / protected full-schema clone.
-- Depends on person_first_candidate.sql and one Course original.
-- This file never reads Titus legacy Course tables and creates no second
-- Course identity, Offering, Session, submission or assigned Work.
-- It does not begin/commit a transaction; clone runner owns rollback.

-- Internal Person/course guard: author must currently resolve from signed
-- Auth and be the same Person who established the canonical Course. Read
-- retired Course history where lawful; all mutations require active Course.
CREATE FUNCTION atlas.require_private_course_author_self_v1(
 p_course_id uuid,p_write boolean
) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $course_guard$
DECLARE v_person uuid; v_course uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_course_id IS NULL THEN
  RAISE EXCEPTION 'authorized Course required' USING ERRCODE='42501';
 END IF;
 IF p_write THEN
  PERFORM titus.require_authoring_access_v1();
  SELECT c.id INTO v_course FROM atlas.teaching_courses c
   WHERE c.id=p_course_id AND c.created_by_person_entity_id=v_person
     AND c.status='active'
   FOR UPDATE;
 ELSE
  SELECT c.id INTO v_course FROM atlas.teaching_courses c
   WHERE c.id=p_course_id AND c.created_by_person_entity_id=v_person;
 END IF;
 IF v_course IS NULL THEN
  RAISE EXCEPTION 'authorized Course required' USING ERRCODE='42501';
 END IF;
 RETURN v_course;
END
$course_guard$;
REVOKE ALL ON FUNCTION atlas.require_private_course_author_self_v1(uuid,boolean)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_course_catalog_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $catalog$
DECLARE v_person uuid;v_courses jsonb;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'courseId',c.id,'title',c.name,
  'state',CASE WHEN c.status='active' THEN 'draft' ELSE 'retired' END,
  'createdAt',c.created_at)
  ORDER BY c.created_at,c.id),'[]'::jsonb) INTO v_courses
 FROM atlas.teaching_courses c WHERE c.created_by_person_entity_id=v_person;
 RETURN jsonb_build_object(
  'contractVersion','shared_teaching_course_catalog_v1','courses',v_courses);
END
$catalog$;

CREATE FUNCTION public.shared_teaching_course_material_read_self_api_v1(
 p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $material_read$
DECLARE v_course uuid; v_revision atlas.teaching_course_manuscript_revisions%ROWTYPE;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 SELECT * INTO v_revision
 FROM atlas.teaching_course_manuscript_revisions r
 WHERE r.course_id=v_course
 ORDER BY r.revision_number DESC LIMIT 1;
 RETURN jsonb_build_object(
  'contractVersion','shared_teaching_course_material_v1',
  'courseId',v_course,
  'material',CASE WHEN v_revision.revision_id IS NULL THEN NULL ELSE
   jsonb_build_object(
    'revisionId',v_revision.revision_id,
    'revisionNumber',v_revision.revision_number,
    'text',v_revision.body_text,
    'savedAt',v_revision.recorded_at) END);
END
$material_read$;

CREATE FUNCTION public.shared_teaching_course_material_save_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_expected_revision integer,p_text text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $material_save$
DECLARE
 v_course uuid;v_person uuid;v_previous atlas.teaching_course_manuscript_revisions%ROWTYPE;
 v_latest integer;
BEGIN
 IF p_request_id IS NULL OR p_expected_revision IS NULL
  OR p_expected_revision<0 OR p_expected_revision>=10000
  OR p_text IS NULL OR char_length(p_text)>40000 THEN
  RAISE EXCEPTION 'invalid manuscript request' USING ERRCODE='22023';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_previous FROM atlas.teaching_course_manuscript_revisions r
 WHERE r.course_id=v_course AND r.edit_request_id=p_request_id;
 IF v_previous.revision_id IS NOT NULL THEN
  IF v_previous.based_on_revision IS DISTINCT FROM p_expected_revision
    OR v_previous.body_text IS DISTINCT FROM p_text THEN
   RAISE EXCEPTION 'replayed manuscript request differs' USING ERRCODE='23505';
  END IF;
  RETURN public.shared_teaching_course_material_read_self_api_v1(v_course);
 END IF;
 SELECT coalesce(max(revision_number),0) INTO v_latest
 FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course;
 IF v_latest<>p_expected_revision THEN
  RAISE EXCEPTION 'stale manuscript revision' USING ERRCODE='40001';
 END IF;
 INSERT INTO atlas.teaching_course_manuscript_revisions(
  course_id,edit_request_id,based_on_revision,revision_number,body_text,
  recorded_by_person_entity_id,recorded_by_auth_user_id)
 VALUES(v_course,p_request_id,v_latest,v_latest+1,p_text,
  v_person,auth.uid());
 RETURN public.shared_teaching_course_material_read_self_api_v1(v_course);
END
$material_save$;

CREATE FUNCTION public.shared_teaching_course_outline_read_self_api_v1(
 p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $outline$
DECLARE v_course uuid;v_units jsonb;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'unitId',u.unit_id,'kind',u.kind,'title',u.title,
  'position',u.display_position,'createdAt',u.created_at)
   ORDER BY u.display_position,u.unit_id),'[]'::jsonb)
 INTO v_units FROM atlas.teaching_course_units u
 WHERE u.course_id=v_course;
 RETURN jsonb_build_object(
  'contractVersion','shared_teaching_course_outline_v1',
  'courseId',v_course,'units',v_units);
END
$outline$;

CREATE FUNCTION public.shared_teaching_course_unit_create_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_kind text,p_title text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $unit_create$
DECLARE
 v_course uuid;v_person uuid;v_title text:=btrim(coalesce(p_title,''));
 v_previous atlas.teaching_course_units%ROWTYPE;
 v_position integer;v_count integer;
BEGIN
 IF p_request_id IS NULL OR p_kind IS NULL
  OR p_kind NOT IN ('lesson','assignment')
  OR length(v_title) NOT BETWEEN 1 AND 150 THEN
  RAISE EXCEPTION 'invalid Unit create request' USING ERRCODE='22023';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_previous FROM atlas.teaching_course_units
 WHERE course_id=v_course AND create_request_id=p_request_id;
 IF v_previous.unit_id IS NOT NULL THEN
  IF v_previous.kind IS DISTINCT FROM p_kind
     OR v_previous.title IS DISTINCT FROM v_title THEN
   RAISE EXCEPTION 'Unit create request changed' USING ERRCODE='23505';
  END IF;
  RETURN public.shared_teaching_course_outline_read_self_api_v1(v_course);
 END IF;
 SELECT count(*),coalesce(max(display_position),0)+1024
 INTO v_count,v_position
 FROM atlas.teaching_course_units WHERE course_id=v_course;
 IF v_count>=100 THEN
  RAISE EXCEPTION 'Course Unit limit reached' USING ERRCODE='22023';
 END IF;
 INSERT INTO atlas.teaching_course_units(
  course_id,create_request_id,kind,title,display_position,
  created_by_person_entity_id,created_by_auth_user_id)
 VALUES(v_course,p_request_id,p_kind,v_title,v_position,v_person,auth.uid());
 RETURN public.shared_teaching_course_outline_read_self_api_v1(v_course);
END
$unit_create$;

CREATE FUNCTION public.shared_teaching_course_unit_move_self_api_v1(
 p_course_id uuid,p_unit_id uuid,p_direction text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $unit_move$
DECLARE
 v_course uuid;v_unit atlas.teaching_course_units%ROWTYPE;
 v_neighbor atlas.teaching_course_units%ROWTYPE;v_temporary integer;
BEGIN
 IF p_unit_id IS NULL OR p_direction IS NULL
 OR p_direction NOT IN ('up','down') THEN
  RAISE EXCEPTION 'invalid Unit move request' USING ERRCODE='22023';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 SELECT * INTO v_unit FROM atlas.teaching_course_units
 WHERE course_id=v_course AND unit_id=p_unit_id;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'authorized Course required' USING ERRCODE='42501';
 END IF;
 IF p_direction='up' THEN
  SELECT * INTO v_neighbor FROM atlas.teaching_course_units
  WHERE course_id=v_course AND display_position<v_unit.display_position
  ORDER BY display_position DESC,unit_id DESC LIMIT 1;
 ELSE
  SELECT * INTO v_neighbor FROM atlas.teaching_course_units
  WHERE course_id=v_course AND display_position>v_unit.display_position
  ORDER BY display_position ASC,unit_id ASC LIMIT 1;
 END IF;
 IF v_neighbor.unit_id IS NOT NULL THEN
  -- The canonical table has an immediate (course_id,position) UNIQUE key.
  -- Three ordered positive-position updates avoid transient uniqueness
  -- failures from a single CASE swap. The Course row lock serializes moves.
  SELECT coalesce(max(display_position),0)+1024 INTO v_temporary
  FROM atlas.teaching_course_units WHERE course_id=v_course;
  UPDATE atlas.teaching_course_units SET display_position=v_temporary
   WHERE unit_id=v_unit.unit_id;
  UPDATE atlas.teaching_course_units SET display_position=v_unit.display_position
   WHERE unit_id=v_neighbor.unit_id;
  UPDATE atlas.teaching_course_units SET display_position=v_neighbor.display_position
   WHERE unit_id=v_unit.unit_id;
 END IF;
 RETURN public.shared_teaching_course_outline_read_self_api_v1(v_course);
END
$unit_move$;

CREATE FUNCTION public.shared_teaching_course_unit_read_self_api_v1(p_unit_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $unit_read$
DECLARE
 v_unit atlas.teaching_course_units%ROWTYPE;
 v_revision atlas.teaching_course_unit_revisions%ROWTYPE;
 v_course uuid;
BEGIN
 IF p_unit_id IS NULL THEN
  RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_unit FROM atlas.teaching_course_units WHERE unit_id=p_unit_id;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(v_unit.course_id,false);
 SELECT * INTO v_revision FROM atlas.teaching_course_unit_revisions
 WHERE unit_id=v_unit.unit_id ORDER BY revision_number DESC LIMIT 1;
 RETURN jsonb_build_object(
  'contractVersion','shared_teaching_course_unit_material_v1',
  'courseId',v_course,
  'unit',jsonb_build_object(
   'unitId',v_unit.unit_id,'kind',v_unit.kind,'title',v_unit.title,
   'position',v_unit.display_position,'createdAt',v_unit.created_at),
  'material',CASE WHEN v_revision.revision_id IS NULL THEN NULL ELSE
  jsonb_build_object(
   'revisionId',v_revision.revision_id,
   'revisionNumber',v_revision.revision_number,
   'text',v_revision.body_text,'savedAt',v_revision.recorded_at) END);
END
$unit_read$;

CREATE FUNCTION public.shared_teaching_course_unit_save_self_api_v1(
 p_unit_id uuid,p_request_id uuid,p_expected_revision integer,p_text text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $unit_save$
DECLARE
 v_unit atlas.teaching_course_units%ROWTYPE;
 v_prev atlas.teaching_course_unit_revisions%ROWTYPE;
 v_person uuid;v_course uuid;v_latest integer;
BEGIN
 IF p_unit_id IS NULL OR p_request_id IS NULL
 OR p_expected_revision IS NULL OR p_expected_revision<0
 OR p_expected_revision>=10000 OR p_text IS NULL
 OR char_length(p_text)>20000 THEN
  RAISE EXCEPTION 'invalid Unit revision write' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_unit FROM atlas.teaching_course_units WHERE unit_id=p_unit_id;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(v_unit.course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_prev FROM atlas.teaching_course_unit_revisions
 WHERE unit_id=p_unit_id AND edit_request_id=p_request_id;
 IF v_prev.revision_id IS NOT NULL THEN
  IF v_prev.based_on_revision IS DISTINCT FROM p_expected_revision
  OR v_prev.body_text IS DISTINCT FROM p_text THEN
   RAISE EXCEPTION 'Unit request changed' USING ERRCODE='23505';
  END IF;
  RETURN public.shared_teaching_course_unit_read_self_api_v1(p_unit_id);
 END IF;
 SELECT coalesce(max(revision_number),0) INTO v_latest
 FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit_id;
 IF v_latest<>p_expected_revision THEN
  RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001';
 END IF;
 INSERT INTO atlas.teaching_course_unit_revisions(
  unit_id,edit_request_id,based_on_revision,revision_number,body_text,
  recorded_by_person_entity_id,recorded_by_auth_user_id)
 VALUES(p_unit_id,p_request_id,v_latest,v_latest+1,p_text,v_person,auth.uid());
 RETURN public.shared_teaching_course_unit_read_self_api_v1(p_unit_id);
END
$unit_save$;

-- Only authenticated self-calls; no direct canonical tables are opened.
REVOKE ALL ON FUNCTION
 public.shared_teaching_course_catalog_self_api_v1(),
 public.shared_teaching_course_material_read_self_api_v1(uuid),
 public.shared_teaching_course_material_save_self_api_v1(uuid,uuid,integer,text),
 public.shared_teaching_course_outline_read_self_api_v1(uuid),
 public.shared_teaching_course_unit_create_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_course_unit_move_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_unit_read_self_api_v1(uuid),
 public.shared_teaching_course_unit_save_self_api_v1(uuid,uuid,integer,text)
FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_catalog_self_api_v1(),
 public.shared_teaching_course_material_read_self_api_v1(uuid),
 public.shared_teaching_course_material_save_self_api_v1(uuid,uuid,integer,text),
 public.shared_teaching_course_outline_read_self_api_v1(uuid),
 public.shared_teaching_course_unit_create_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_course_unit_move_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_unit_read_self_api_v1(uuid),
 public.shared_teaching_course_unit_save_self_api_v1(uuid,uuid,integer,text)
TO authenticated;

-- Existing transferable pilot code issuance and recipient claim.
-- HELD M1.1 owner correction 6D/7C/5B: one transferable private-pilot code.
-- Not a generated migration; requires protected clone and owner review.
-- Single-claim behavior is a bounded test policy, NOT a final business choice
-- about multi-seat code capacity, code expiry, paid plans, or free trials.
-- No real owner/delegated Titus issuer standing is established by this file.
DO $preflight$
BEGIN
 IF to_regclass('reality.responsibility_relations') IS NULL
 OR to_regclass('titus.course_authoring_access_grants') IS NULL
 OR to_regclass('titus.course_authoring_access_status_events') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held Titus pilot source prerequisites missing'
  USING ERRCODE='42501';
 END IF;
END $preflight$;

-- Role source is Reality's actual active domain responsibility; a signed
-- Titus user, Course author, institution teacher or product purchaser does
-- NOT automatically become a platform issuer. The private helper itself is
-- not callable via PostgREST.
CREATE FUNCTION titus.require_current_pilot_issuer_self_v1(
 p_operation text
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $issuer$
DECLARE v_person uuid;v_ids uuid[];
BEGIN
 IF p_operation NOT IN
  ('issue_pilot_code','revoke_pilot_code','end_pilot_access') THEN
  RAISE EXCEPTION 'exact Titus platform issuance operation required'
   USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT array_agg(r.id) INTO v_ids
 FROM reality.responsibility_relations r
 WHERE r.carrier_person_entity_id=v_person
  AND r.responsibility_key='titus_private_pilot_issuance'
  AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
  AND r.relation_state='active'
  AND r.began_at<=clock_timestamp()
  AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
  AND p_operation=ANY(r.permitted_operations);
 IF COALESCE(array_length(v_ids,1),0)<>1 THEN
  RAISE EXCEPTION 'one current authorized Titus platform issuer required'
   USING ERRCODE='42501';
 END IF;
 RETURN v_ids[1];
END $issuer$;
REVOKE ALL ON FUNCTION titus.require_current_pilot_issuer_self_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;

-- A code is not addressed to a particular Person when created.
-- Store ONLY SHA-256 of a uniformly random 244-bit token. The original token
-- is returned ONCE to the signed issuer in that initial RPC; never stored.
CREATE TABLE titus.course_authoring_pilot_codes(
 code_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_hash text NOT NULL UNIQUE CHECK(
   code_hash ~ '^[0-9a-f]{64}$'),
 issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL
  REFERENCES reality.responsibility_relations(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(issuer_person_entity_id,request_id)
);
CREATE TABLE titus.course_authoring_pilot_code_claims(
 claim_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_id uuid NOT NULL UNIQUE REFERENCES
   titus.course_authoring_pilot_codes(code_id) ON DELETE RESTRICT,
 claimed_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 claimed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(claimed_by_person_entity_id,request_id)
);
CREATE TABLE titus.course_authoring_pilot_code_cancellations(
 cancellation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 code_id uuid NOT NULL UNIQUE REFERENCES
  titus.course_authoring_pilot_codes(code_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 cancelled_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 issuer_responsibility_id uuid NOT NULL REFERENCES
  reality.responsibility_relations(id) ON DELETE RESTRICT,
 cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(cancelled_by_person_entity_id,request_id)
);
ALTER TABLE titus.course_authoring_pilot_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.course_authoring_pilot_code_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.course_authoring_pilot_code_cancellations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.course_authoring_pilot_codes,
 titus.course_authoring_pilot_code_claims,
 titus.course_authoring_pilot_code_cancellations
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION titus.reject_pilot_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Titus pilot code, claim or cancellation cannot be rewritten'
  USING ERRCODE='55000';
END $immutable$;
REVOKE ALL ON FUNCTION titus.reject_pilot_original_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER titus_pilot_code_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_codes
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();
CREATE TRIGGER titus_pilot_claim_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_code_claims
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();
CREATE TRIGGER titus_pilot_cancel_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.course_authoring_pilot_code_cancellations
 FOR EACH ROW EXECUTE FUNCTION titus.reject_pilot_original_mutation_v1();

-- A signed, source-authorized platform issuer creates a bearer code. No
-- recipient Person exists or is chosen here. No license is created yet.
CREATE FUNCTION public.titus_private_pilot_code_issue_self_api_v1(
 p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $issue$
DECLARE v_person uuid;v_auth uuid;v_authority uuid;
 v_old titus.course_authoring_pilot_codes%ROWTYPE;
 v_code text;v_hash text;v_id uuid;
BEGIN
 IF p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact pilot code issuance request required'
   USING ERRCODE='22023';
 END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('issue_pilot_code');
 v_person:=atlas.current_person_for_private_course_v1();
 v_auth:=auth.uid();
 SELECT * INTO v_old FROM titus.course_authoring_pilot_codes c
 WHERE c.issuer_person_entity_id=v_person AND c.request_id=p_request_id;
 IF v_old.code_id IS NOT NULL THEN
  IF v_old.issuer_auth_user_id IS DISTINCT FROM v_auth
    OR v_old.issuer_responsibility_id IS DISTINCT FROM v_authority THEN
   RAISE EXCEPTION 'pilot issuance retry had changed authority'
    USING ERRCODE='23505'; END IF;
  -- Never reveal a bearer secret again on replay.
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_issue_v1',
   'codeId',v_old.code_id,'alreadyExists',true,'secretAvailable',false);
 END IF;
 v_code:='TITUS-'||
  upper(replace(gen_random_uuid()::text,'-','')||
        replace(gen_random_uuid()::text,'-',''));
 v_hash:=encode(sha256(convert_to(v_code,'UTF8')),'hex');
 INSERT INTO titus.course_authoring_pilot_codes(
  code_hash,issuer_person_entity_id,issuer_auth_user_id,
  issuer_responsibility_id,request_id)
 VALUES(v_hash,v_person,v_auth,v_authority,p_request_id)
 RETURNING code_id INTO v_id;
 -- One-time secret: transmit only through the actual signed response,
 -- never write it into table, event log, URL, analytics or debug output.
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_issue_v1',
  'codeId',v_id,'code',v_code,
  'alreadyExists',false,'secretAvailable',true,
  'grantActive',false,'claimCapacity',1);
END $issue$;

-- A transferable bearer may be passed before claim. Its *actual* first
-- claimant must be a current independently signed canonical Reality Person.
-- Lock exact code row to serialize competing simultaneous claims/cancels;
-- a consumed or cancelled bearer can never mint a second license.
CREATE FUNCTION public.titus_private_pilot_code_claim_self_api_v1(
 p_code text,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $claim$
DECLARE v_person uuid;v_code titus.course_authoring_pilot_codes%ROWTYPE;
 v_old titus.course_authoring_pilot_code_claims%ROWTYPE;v_hash text;
BEGIN
 IF p_request_id IS NULL OR p_code IS NULL OR
 p_code !~ '^TITUS-[A-F0-9]{64}$' THEN
  RAISE EXCEPTION 'valid Titus pilot code required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 v_hash:=encode(sha256(convert_to(p_code,'UTF8')),'hex');
 SELECT * INTO v_code FROM titus.course_authoring_pilot_codes c
 WHERE c.code_hash=v_hash FOR UPDATE;
 IF v_code.code_id IS NULL THEN
  RAISE EXCEPTION 'unavailable pilot code' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_pilot_code_claims x
 WHERE x.code_id=v_code.code_id;
 IF v_old.claim_id IS NOT NULL THEN
  IF v_old.claimed_by_person_entity_id IS DISTINCT FROM v_person
  OR v_old.request_id IS DISTINCT FROM p_request_id THEN
   RAISE EXCEPTION 'pilot code already claimed'
    USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_claim_v1',
   'codeId',v_code.code_id,'alreadyExists',true,
   'grantActive',titus.authoring_grant_current_active_v1(v_person));
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_cancellations x
   WHERE x.code_id=v_code.code_id) OR v_person=v_code.issuer_person_entity_id THEN
  RAISE EXCEPTION 'unavailable pilot code' USING ERRCODE='42501'; END IF;
 -- Issuer may have delegated/ceased authority since creating code.
 IF NOT EXISTS(
  SELECT 1 FROM reality.responsibility_relations r
  WHERE r.id=v_code.issuer_responsibility_id
   AND r.carrier_person_entity_id=v_code.issuer_person_entity_id
   AND r.responsibility_key='titus_private_pilot_issuance'
   AND r.jurisdiction_kind='domain' AND r.jurisdiction_domain='titus'
   AND r.relation_state='active'
   AND r.began_at<=clock_timestamp()
   AND (r.ended_at IS NULL OR r.ended_at>clock_timestamp())
   AND 'issue_pilot_code'=ANY(r.permitted_operations)
   AND EXISTS(
    SELECT 1 FROM reality.auth_person_bindings b
    JOIN reality.entities issuer ON issuer.id=b.person_entity_id
    WHERE b.auth_user_id=v_code.issuer_auth_user_id
     AND b.person_entity_id=v_code.issuer_person_entity_id
     AND b.binding_state='active' AND b.retired_at IS NULL
     AND issuer.entity_kind='person' AND issuer.identity_state='canonical')
 ) THEN
  RAISE EXCEPTION 'pilot code issuer is no longer authorized'
   USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_access_grants g
   WHERE g.person_entity_id=v_person) THEN
  RAISE EXCEPTION 'Person already has Titus product grant'
   USING ERRCODE='23505'; END IF;
 INSERT INTO titus.course_authoring_pilot_code_claims(
  code_id,claimed_by_person_entity_id,request_id)
 VALUES(v_code.code_id,v_person,p_request_id);
 INSERT INTO titus.course_authoring_access_grants(
  person_entity_id,grant_source_auth_user_id,grant_kind,
  grant_source_receipt,state,granted_at,valid_until)
 VALUES(v_person,v_code.issuer_auth_user_id,'private_pilot',
  'pilotcode:'||v_code.code_id::text,'active',clock_timestamp(),NULL);
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_claim_v1',
  'codeId',v_code.code_id,'alreadyExists',false,
  'grantActive',titus.authoring_grant_current_active_v1(v_person));
END $claim$;

-- A distinct currently authorized platform admin may cancel an unclaimed
-- code. This is an append-only event, not a mutable expiration field.
CREATE FUNCTION public.titus_private_pilot_code_cancel_self_api_v1(
 p_code_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $cancel$
DECLARE v_actor uuid;v_authority uuid;
 v_code titus.course_authoring_pilot_codes%ROWTYPE;
 v_old titus.course_authoring_pilot_code_cancellations%ROWTYPE;
BEGIN
 IF p_code_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact code cancellation required' USING ERRCODE='22023'; END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('revoke_pilot_code');
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_code FROM titus.course_authoring_pilot_codes c
 WHERE c.code_id=p_code_id FOR UPDATE;
 IF v_code.code_id IS NULL THEN
  RAISE EXCEPTION 'known pilot code required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_pilot_code_cancellations x
 WHERE x.code_id=p_code_id;
 IF v_old.cancellation_id IS NOT NULL THEN
  IF v_old.cancelled_by_person_entity_id IS DISTINCT FROM v_actor
  OR v_old.request_id IS DISTINCT FROM p_request_id THEN
   RAISE EXCEPTION 'changed code cancellation replay'
    USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_code_cancel_v1',
   'codeId',p_code_id,'alreadyExists',true);
 END IF;
 IF EXISTS(SELECT 1 FROM titus.course_authoring_pilot_code_claims x
   WHERE x.code_id=p_code_id) THEN
  RAISE EXCEPTION 'claimed pilot code cannot be cancelled'
   USING ERRCODE='23514'; END IF;
 INSERT INTO titus.course_authoring_pilot_code_cancellations(
  code_id,request_id,cancelled_by_person_entity_id,issuer_responsibility_id)
 VALUES(p_code_id,p_request_id,v_actor,v_authority);
 RETURN jsonb_build_object('contractVersion','titus_pilot_code_cancel_v1',
  'codeId',p_code_id,'alreadyExists',false);
END $cancel$;

-- No automatic expiration on an accepted pilot. Ending it is a deliberate
-- source-audited, independently authorized Titus administrator operation.
CREATE FUNCTION public.titus_private_pilot_access_end_self_api_v1(
 p_grantee_person uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog AS $end_pilot$
DECLARE v_actor uuid;v_authority uuid;
 v_grant titus.course_authoring_access_grants%ROWTYPE;
 v_old titus.course_authoring_access_status_events%ROWTYPE;
BEGIN
 IF p_grantee_person IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact administrator pilot end decision required'
   USING ERRCODE='22023'; END IF;
 v_authority:=titus.require_current_pilot_issuer_self_v1('end_pilot_access');
 v_actor:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_grant FROM titus.course_authoring_access_grants g
 WHERE g.person_entity_id=p_grantee_person FOR UPDATE;
 IF v_grant.person_entity_id IS NULL
 OR v_grant.grant_kind IS DISTINCT FROM 'private_pilot'
 OR v_grant.grant_source_receipt NOT LIKE 'pilotcode:%'
 THEN RAISE EXCEPTION 'original claimed pilot grant required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM titus.course_authoring_access_status_events e
 WHERE e.person_entity_id=p_grantee_person AND e.request_id=p_request_id;
 IF v_old.event_seq IS NOT NULL THEN
  IF v_old.next_state IS DISTINCT FROM 'revoked' OR
    v_old.recorded_by_auth_user_id IS DISTINCT FROM auth.uid() THEN
   RAISE EXCEPTION 'changed pilot end replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','titus_pilot_access_end_v1',
   'ended',true,'alreadyExists',true);
 END IF;
 INSERT INTO titus.course_authoring_access_status_events(
  person_entity_id,request_id,next_state,source_evidence_receipt,
  recorded_by_auth_user_id)
 VALUES(p_grantee_person,p_request_id,'revoked',
  'pilotend:'||p_request_id::text,auth.uid());
 RETURN jsonb_build_object('contractVersion','titus_pilot_access_end_v1',
  'ended',true,'alreadyExists',false);
END $end_pilot$;

REVOKE ALL ON FUNCTION
 public.titus_private_pilot_code_issue_self_api_v1(uuid),
 public.titus_private_pilot_code_claim_self_api_v1(text,uuid),
 public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid),
 public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
 public.titus_private_pilot_code_issue_self_api_v1(uuid),
 public.titus_private_pilot_code_claim_self_api_v1(text,uuid),
 public.titus_private_pilot_code_cancel_self_api_v1(uuid,uuid),
 public.titus_private_pilot_access_end_self_api_v1(uuid,uuid)
 TO authenticated;
-- Paid purchase, free trial, actual license issuer, organizational license,
-- post-license read/export, rate-limit/claim capacity, browser delivery,
-- protected GoTrue signed proof and production release are all STILL HELD.

COMMIT;
