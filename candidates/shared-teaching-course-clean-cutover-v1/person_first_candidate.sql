-- PERSON-FIRST CANONICAL COURSE — M1 CANDIDATE, NOT A GENERATED MIGRATION.
-- PRIVATE, disposable full-schema PG clone ONLY. DO NOT RUN ON PRODUCTION.
-- Exact request: owner 1A/2D/3D (Nov 7 2026). No real SK101 text in source.
-- Must first set LOCAL app.shared_course_clone = 'approved' inside clone transaction.
-- Does NOT yet migrate SK101 content, switch Titus readers/writers, publish,
-- create institution standing, or delete any legacy table. HOLD pending signed tests.
-- Protected clone harness: BEGIN; SET LOCAL app.shared_course_clone='approved';
-- source this candidate; ROLLBACK for smoke, COMMIT only on disposable clone.
-- This candidate itself owns neither the transaction nor the approval.
DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'protected clone marker required; no production execution' USING ERRCODE='42501';
 END IF;
 IF EXISTS (SELECT 1 FROM atlas.teaching_courses) THEN
  RAISE EXCEPTION 'canonical root not empty; review identity collisions first' USING ERRCODE='23514';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_drafts_v1) <> 1 THEN
  RAISE EXCEPTION 'source snapshot drift; abort and recalculate protected inventory' USING ERRCODE='23514';
 END IF;
END;
$guard$;

-- This is an adaptation of the canonical root, NOT a second Course table.
-- Ledger/Principal/activation are institutional relations, not Course identity.
ALTER TABLE atlas.teaching_courses
 ADD COLUMN created_by_person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN create_request_id uuid,
 ADD COLUMN created_by_auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ALTER COLUMN ledger_id DROP NOT NULL,
 ALTER COLUMN capability_activation_id DROP NOT NULL,
 ALTER COLUMN created_by_person_id DROP NOT NULL,
 ALTER COLUMN created_by_principal_id DROP NOT NULL;
ALTER TABLE atlas.teaching_courses
 ALTER COLUMN created_by_person_entity_id SET NOT NULL,
 ALTER COLUMN create_request_id SET NOT NULL;
CREATE UNIQUE INDEX teaching_courses_person_request_v1
 ON atlas.teaching_courses(created_by_person_entity_id,create_request_id);

-- Former triggers enforced Ledger activation at Course creation and
-- immutable Principal/ledger claims. Those are no longer root Course facts.
-- Existing old Ledger-first creation RPCs become held until replacement and
-- must be retired, not regranted, as part of the final M3/M4 source cutover.
DROP TRIGGER teaching_courses_activation_guard_v1 ON atlas.teaching_courses;
DROP TRIGGER teaching_courses_identity_immutable_v1 ON atlas.teaching_courses;

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
REVOKE ALL ON FUNCTION atlas.guard_person_course_identity_v1() FROM PUBLIC;
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
REVOKE ALL ON atlas.teaching_course_manuscript_revisions FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_units FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_unit_revisions FROM PUBLIC,anon,authenticated;

-- No Person ID comes from client input; active Reality credential binding
-- is the only subject resolver. Must have exactly one canonical Person.
CREATE FUNCTION atlas.current_person_for_private_course_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog
AS $$
DECLARE v_people uuid[]; v_auth uuid;
BEGIN
 v_auth:=auth.uid();
 IF v_auth IS NULL THEN
  RAISE EXCEPTION 'signed Person required' USING ERRCODE='42501';
 END IF;
 SELECT array_agg(b.person_entity_id) INTO v_people
 FROM reality.auth_person_bindings b JOIN reality.entities e
   ON e.id=b.person_entity_id AND e.entity_kind='person'
 WHERE b.auth_user_id=v_auth AND b.binding_state='active';
 IF coalesce(array_length(v_people,1),0)<>1 THEN
  RAISE EXCEPTION 'unique current canonical Person required' USING ERRCODE='42501';
 END IF;
 RETURN v_people[1];
END
$$;
REVOKE ALL ON FUNCTION atlas.current_person_for_private_course_v1() FROM PUBLIC,anon,authenticated;

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
 v_person:=atlas.current_person_for_private_course_v1();
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
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_teaching_course_create_self_api_v1(uuid,text)
 TO authenticated;

-- This candidate is deliberately not the full source release. No migration of
-- real founder material, new Unit writers, institutional standing or deletion.
-- The follow-up clone tranche must replace all old writer/readers atomically.
-- End M1 candidate. No transaction is committed by this file.
