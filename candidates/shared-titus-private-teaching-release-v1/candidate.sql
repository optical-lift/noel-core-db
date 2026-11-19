-- HELD RELEASE-SHAPED REVIEW CANDIDATE ONLY. Not a migration or authorization.
-- Provenance: Noel #2617 e71fc75d37a047ec52ebbace72fb7698fec00284; protected test 44565774815.
-- Governance: separate canonical migration, clone rehearsal and owner release.
-- No clone marker, no seed, no legacy retirement or real enrollment.
BEGIN;

-- Release-shaped prerequisite and collision assertions; no source rows read.
DO $base$
DECLARE name text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 THEN RAISE EXCEPTION 'PG17 required';END IF;
 FOREACH name IN ARRAY ARRAY['atlas.teaching_courses','atlas.teaching_course_versions',
 'atlas.teaching_course_manuscript_revisions','atlas.teaching_course_units','atlas.teaching_course_unit_revisions',
 'reality.entities','reality.auth_person_bindings','titus.course_authoring_access_grants']
 LOOP IF to_regclass(name) IS NULL THEN RAISE EXCEPTION 'released base relation absent: %',name;END IF;END LOOP;
 FOREACH name IN ARRAY ARRAY['atlas.require_private_course_author_self_v1(uuid,boolean)',
 'atlas.current_person_for_private_course_v1()','public.titus_authoring_access_self_api_v1()',
 'public.shared_teaching_course_adopt_self_api_v1(uuid)']
 LOOP IF to_regprocedure(name) IS NULL THEN RAISE EXCEPTION 'released base function absent: %',name;END IF;END LOOP;
 FOREACH name IN ARRAY ARRAY['atlas.teaching_course_composition_revisions',
 'atlas.teaching_course_version_curriculum_snapshots',
 'atlas.teaching_course_private_study_invitations',
 'atlas.teaching_course_private_study_responses',
 'atlas.teaching_course_private_study_terminations',
 'atlas.teaching_course_private_study_unit_decisions',
 'atlas.teaching_course_private_study_answer_revisions',
 'atlas.teaching_course_private_answer_submissions',
 'atlas.teaching_course_private_answer_review_events']
 LOOP IF to_regclass(name) IS NOT NULL THEN RAISE EXCEPTION 'overlapping held source: %',name;END IF;END LOOP;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='atlas.teaching_course_versions'::regclass
 AND attname IN ('published_by_person_entity_id','publication_request_id','publication_scope') AND NOT attisdropped)
 THEN RAISE EXCEPTION 'overlapping Version source: reconcile before install'; END IF;
END $base$;

-- SOURCE MODULE 1: candidates/shared-course-class-composition-v1/candidate.sql
-- HELD: private, Person-origin Course working composition, no seeds or release.
CREATE TABLE atlas.teaching_course_composition_revisions (
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 edit_request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK (based_on_revision BETWEEN 0 AND 9999),
 revision_number integer NOT NULL CHECK (revision_number=based_on_revision+1),
 members jsonb NOT NULL CHECK (jsonb_typeof(members)='array' AND jsonb_array_length(members)<=99),
 recorded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(course_id,edit_request_id), UNIQUE(course_id,revision_number)
);
ALTER TABLE atlas.teaching_course_composition_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_composition_revisions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION atlas.reject_course_composition_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog AS $$
BEGIN RAISE EXCEPTION 'composition revisions are append only' USING ERRCODE='23514'; END $$;
CREATE TRIGGER course_composition_immutable BEFORE UPDATE OR DELETE
 ON atlas.teaching_course_composition_revisions FOR EACH ROW
 EXECUTE FUNCTION atlas.reject_course_composition_mutation_v1();
CREATE TRIGGER course_composition_no_truncate BEFORE TRUNCATE
 ON atlas.teaching_course_composition_revisions FOR EACH STATEMENT
 EXECUTE FUNCTION atlas.reject_course_composition_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_course_composition_mutation_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Validate every reference against the original Course Units, not title or position.
-- A root lesson may not also be a child; no chains or cycles. Detached Units are valid.
-- Depth is presentation intent only, never a learner permission.
CREATE FUNCTION atlas.validate_course_composition_v1(p_course_id uuid,p_members jsonb)
RETURNS void LANGUAGE plpgsql SET search_path TO pg_catalog AS $$
DECLARE item jsonb; child_id uuid; parent_id uuid; children uuid[]:=ARRAY[]::uuid[];
 parents uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF p_members IS NULL OR jsonb_typeof(p_members) IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'invalid composition' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_members)>99 THEN
  RAISE EXCEPTION 'composition limit' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_members) LOOP
  IF jsonb_typeof(item) IS DISTINCT FROM 'object' THEN
   RAISE EXCEPTION 'invalid member' USING ERRCODE='22023'; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(item))<>3
    OR NOT (item ?& ARRAY['unitId','classUnitId','depth'])
    OR jsonb_typeof(item->'unitId') IS DISTINCT FROM 'string'
    OR jsonb_typeof(item->'classUnitId') IS DISTINCT FROM 'string'
    OR jsonb_typeof(item->'depth') IS DISTINCT FROM 'string'
    OR item->>'depth' NOT IN ('foundational','advanced')
    OR (item->>'unitId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    OR (item->>'classUnitId') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'invalid member' USING ERRCODE='22023'; END IF;
  child_id:=(item->>'unitId')::uuid;parent_id:=(item->>'classUnitId')::uuid;
  IF child_id=parent_id OR child_id=ANY(children) THEN
   RAISE EXCEPTION 'duplicate or self member' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u WHERE u.course_id=p_course_id AND u.unit_id=child_id)
   OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u WHERE u.course_id=p_course_id AND u.unit_id=parent_id AND u.kind='lesson') THEN
   RAISE EXCEPTION 'authorized same Course lesson and member required' USING ERRCODE='42501'; END IF;
  children:=array_append(children,child_id);parents:=array_append(parents,parent_id);
 END LOOP;
 IF children && parents THEN RAISE EXCEPTION 'nested class membership prohibited' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION atlas.validate_course_composition_v1(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.course_composition_receipt_v1(p_row atlas.teaching_course_composition_revisions)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog AS $$
 SELECT jsonb_build_object('contractVersion','shared_teaching_course_composition_v1',
 'courseId',p_row.course_id,'revisionNumber',p_row.revision_number,'revisionId',p_row.revision_id,
 'requestId',p_row.edit_request_id,'members',p_row.members,'savedAt',p_row.recorded_at)
$$;
REVOKE ALL ON FUNCTION atlas.course_composition_receipt_v1(atlas.teaching_course_composition_revisions) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_course_composition_read_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_course uuid;v_last atlas.teaching_course_composition_revisions%ROWTYPE;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 SELECT * INTO v_last FROM atlas.teaching_course_composition_revisions
 WHERE course_id=v_course ORDER BY revision_number DESC LIMIT 1;
 IF v_last.revision_id IS NULL THEN
  RETURN jsonb_build_object('contractVersion','shared_teaching_course_composition_v1',
   'courseId',v_course,'revisionNumber',0,'revisionId',NULL,'requestId',NULL,'members','[]'::jsonb,'savedAt',NULL);
 END IF;
 PERFORM atlas.validate_course_composition_v1(v_course,v_last.members);
 RETURN atlas.course_composition_receipt_v1(v_last);
END $$;

CREATE FUNCTION public.shared_teaching_course_composition_save_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_expected_revision integer,p_members jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_course uuid;v_person uuid;v_current integer;
 v_previous atlas.teaching_course_composition_revisions%ROWTYPE;
BEGIN
 IF p_request_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision NOT BETWEEN 0 AND 9999 THEN
  RAISE EXCEPTION 'invalid composition save request' USING ERRCODE='22023'; END IF;
 -- Existing canonical guard resolves signed identity, checks current product
 -- authority, and locks the Course row to serialize all working author writes.
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 PERFORM atlas.validate_course_composition_v1(v_course,p_members);
 SELECT * INTO v_previous FROM atlas.teaching_course_composition_revisions
 WHERE course_id=v_course AND edit_request_id=p_request_id;
 IF v_previous.revision_id IS NOT NULL THEN
  IF v_previous.based_on_revision IS DISTINCT FROM p_expected_revision
   OR v_previous.members IS DISTINCT FROM p_members
   OR v_previous.recorded_by_person_entity_id IS DISTINCT FROM v_person
   OR v_previous.recorded_by_auth_user_id IS DISTINCT FROM auth.uid() THEN
   RAISE EXCEPTION 'composition request changed' USING ERRCODE='23505'; END IF;
  RETURN atlas.course_composition_receipt_v1(v_previous);
 END IF;
 SELECT coalesce(max(revision_number),0) INTO v_current
 FROM atlas.teaching_course_composition_revisions WHERE course_id=v_course;
 IF v_current<>p_expected_revision THEN
  RAISE EXCEPTION 'composition revision conflict' USING ERRCODE='40001'; END IF;
 INSERT INTO atlas.teaching_course_composition_revisions
 (course_id,edit_request_id,based_on_revision,revision_number,members,
 recorded_by_person_entity_id,recorded_by_auth_user_id)
 VALUES(v_course,p_request_id,v_current,v_current+1,p_members,v_person,auth.uid())
 RETURNING * INTO v_previous;
 RETURN atlas.course_composition_receipt_v1(v_previous);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_course_composition_read_self_api_v1(uuid),
 public.shared_teaching_course_composition_save_self_api_v1(uuid,uuid,integer,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_course_composition_read_self_api_v1(uuid),
 public.shared_teaching_course_composition_save_self_api_v1(uuid,uuid,integer,jsonb)
 TO authenticated;

-- SOURCE MODULE 2: candidates/shared-teaching-course-clean-cutover-v1/person_published_definition_candidate.sql
-- HELD M3.9: one immutable definition METADATA version, on existing Course.
-- Author retains root custody. A Version is NOT manuscript or Unit release.
-- Clone-only; no direct DB grants or institutional Course-operation grant.
DO $source_guard$
BEGIN
 IF to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)')
    IS NULL
 OR to_regclass('atlas.teaching_course_versions') IS NULL THEN
  RAISE EXCEPTION 'held Course definition source prerequisites missing'
    USING ERRCODE='42501';
 END IF;
END $source_guard$;

-- The old institutional definition writer required a legacy atlas Person AND
-- Principal. A canonical Person-origin Course must have no such dependency.
-- Existing immutable Version originals (if any) are never rewritten.
ALTER TABLE atlas.teaching_course_versions
 ALTER COLUMN published_by_person_id DROP NOT NULL,
 ALTER COLUMN published_by_principal_id DROP NOT NULL,
 ADD COLUMN published_by_person_entity_id uuid
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN publication_request_id uuid,
 ADD COLUMN publication_scope text NOT NULL DEFAULT 'definition_metadata_only'
   CHECK(publication_scope='definition_metadata_only'),
 ADD CONSTRAINT teaching_course_version_exact_request_uq
   UNIQUE(course_id,publication_request_id);

ALTER TABLE atlas.teaching_course_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_versions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_course_definition_publish_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_title text,p_summary text,p_outcomes text[]
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $publish$
DECLARE
 v_course uuid;
 v_person uuid;
 v_title text:=btrim(coalesce(p_title,''));
 v_summary text:=nullif(btrim(coalesce(p_summary,'')),'');
 v_outcomes text[]:=coalesce(p_outcomes,ARRAY[]::text[]);
 v_old atlas.teaching_course_versions%ROWTYPE;
 v_new atlas.teaching_course_versions%ROWTYPE;
 v_no integer;
BEGIN
 IF p_request_id IS NULL OR length(v_title) NOT BETWEEN 1 AND 150
 OR length(coalesce(v_summary,''))>2000
 OR cardinality(v_outcomes)>30 OR EXISTS(
  SELECT 1 FROM unnest(v_outcomes) o
  WHERE o IS NULL OR length(btrim(o)) NOT BETWEEN 1 AND 500
 ) THEN
  RAISE EXCEPTION 'valid version metadata and request required'
    USING ERRCODE='22023';
 END IF;
 -- Locks actual active Course and verifies signed current Reality Person.
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();

 SELECT * INTO v_old FROM atlas.teaching_course_versions
 WHERE course_id=v_course AND publication_request_id=p_request_id;
 IF v_old.id IS NOT NULL THEN
  IF v_old.published_by_person_entity_id IS DISTINCT FROM v_person
  OR v_old.title IS DISTINCT FROM v_title
  OR v_old.summary IS DISTINCT FROM v_summary
  OR v_old.learning_outcomes IS DISTINCT FROM v_outcomes
  OR v_old.publication_scope<>'definition_metadata_only' THEN
   RAISE EXCEPTION 'changed immutable Course Version request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_definition_publish_v1',
   'courseId',v_course,'courseVersionId',v_old.id,
   'versionNo',v_old.version_no,'publicationScope',v_old.publication_scope,
   'alreadyExists',true,'institutionCanUse',false);
 END IF;

 SELECT coalesce(max(version_no),0)+1 INTO v_no
 FROM atlas.teaching_course_versions WHERE course_id=v_course;
 INSERT INTO atlas.teaching_course_versions(
  course_id,version_no,title,summary,learning_outcomes,
  published_by_person_entity_id,publication_request_id,publication_scope
 ) VALUES (
  v_course,v_no,v_title,v_summary,v_outcomes,
  v_person,p_request_id,'definition_metadata_only'
 ) RETURNING * INTO v_new;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_definition_publish_v1',
  'courseId',v_course,'courseVersionId',v_new.id,
  'versionNo',v_new.version_no,'publicationScope',v_new.publication_scope,
  'alreadyExists',false,'institutionCanUse',false);
END $publish$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])
 TO authenticated;

-- Deliberately no institutional Version reader or Offering writer here.
-- Version immutability relies on the existing BEFORE UPDATE OR DELETE
-- atlas.reject_teaching_course_version_mutation_v1 trigger (verified in clone).

-- SOURCE MODULE 3: candidates/shared-teaching-course-clean-cutover-v1/person_course_curriculum_snapshot_candidate.sql
-- HELD M3.11 — ONE immutable, privately sealed curriculum snapshot per
-- Person-authored Course Version. This is not institutional disclosure,
-- Course root creation, Offering opening, teacher appointment, or enrollment.
-- The previous M3.9 published Version is definition metadata ONLY. Its
-- historical identity remains unchanged; a distinct author decision copies
-- its own current manuscript + ordered complete Unit revisions at seal time.
-- Applied only on disposable PostgreSQL 17/protected clone, never production.
DO $source_guard$
BEGIN
 IF to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regclass('atlas.teaching_course_versions') IS NULL
 OR to_regclass('atlas.teaching_course_manuscript_revisions') IS NULL
 OR to_regclass('atlas.teaching_course_units') IS NULL
 OR to_regclass('atlas.teaching_course_unit_revisions') IS NULL THEN
  RAISE EXCEPTION 'protected complete-Course authoring source required'
   USING ERRCODE='42501';
 END IF;
END $source_guard$;

CREATE TABLE atlas.teaching_course_version_curriculum_snapshots (
 snapshot_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL,
 course_version_id uuid NOT NULL,
 sealing_request_id uuid NOT NULL,
 sealed_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 curriculum_payload jsonb NOT NULL CHECK (
  jsonb_typeof(curriculum_payload)='object'
  AND curriculum_payload->>'format'='shared_course_curriculum_snapshot_v1'
 ),
 sealed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(course_id,course_version_id)
  REFERENCES atlas.teaching_course_versions(course_id,id) ON DELETE RESTRICT,
 UNIQUE(course_version_id),
 UNIQUE(course_id,sealing_request_id)
);
ALTER TABLE atlas.teaching_course_version_curriculum_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_version_curriculum_snapshots
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_curriculum_snapshot_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $immutable$
BEGIN
 RAISE EXCEPTION 'Sealed Course curriculum snapshots are immutable.'
  USING ERRCODE='55000';
END $immutable$;
CREATE TRIGGER teaching_course_curriculum_snapshot_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_version_curriculum_snapshots
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_curriculum_snapshot_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_curriculum_snapshot_mutation_v1()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_course_curriculum_seal_self_api_v1(
 p_course_id uuid,p_course_version_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $seal$
DECLARE
 v_course uuid;
 v_person uuid;
 v_version atlas.teaching_course_versions%ROWTYPE;
 v_previous atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_manuscript atlas.teaching_course_manuscript_revisions%ROWTYPE;
 v_units jsonb;
 v_unit_count bigint;
 v_revision_count bigint;
 v_complete_count bigint;
 v_payload jsonb;
 v_composition jsonb;
 v_snapshot_id uuid;
BEGIN
 IF p_course_id IS NULL OR p_course_version_id IS NULL
 OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact authored Course, Version and sealing request required'
   USING ERRCODE='22023';
 END IF;
 -- Every author manuscript/Unit write in M3 also takes the same Course row
 -- lock; sealing observes one serialized, complete revision boundary.
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_version FROM atlas.teaching_course_versions
 WHERE id=p_course_version_id AND course_id=v_course
   AND published_by_person_entity_id=v_person
   AND publication_scope='definition_metadata_only';
 IF v_version.id IS NULL THEN
  RAISE EXCEPTION 'own immutable Person-published Course Version required'
   USING ERRCODE='42501';
 END IF;

 -- A Version has exactly one sealed curriculum. Retry identity cannot
 -- reseal or silently adopt newer revisions after the original capture.
 SELECT * INTO v_previous
 FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_version_id=v_version.id;
 IF v_previous.snapshot_id IS NOT NULL THEN
  IF v_previous.sealing_request_id IS DISTINCT FROM p_request_id
  OR v_previous.sealed_by_person_entity_id IS DISTINCT FROM v_person
  OR v_previous.course_id IS DISTINCT FROM v_course THEN
   RAISE EXCEPTION 'immutable curriculum snapshot request changed'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_curriculum_seal_v1',
   'courseId',v_course,'courseVersionId',v_version.id,
   'snapshotId',v_previous.snapshot_id,'alreadyExists',true,
   'institutionCanRead',false,'canOpenOffering',false);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_version_curriculum_snapshots s
   WHERE s.course_id=v_course AND s.sealing_request_id=p_request_id) THEN
  RAISE EXCEPTION 'sealing request cannot be reused for another Version'
   USING ERRCODE='23505';
 END IF;

 SELECT * INTO v_manuscript
 FROM atlas.teaching_course_manuscript_revisions m
 WHERE m.course_id=v_course ORDER BY m.revision_number DESC LIMIT 1;
 IF v_manuscript.revision_id IS NULL
 OR length(btrim(v_manuscript.body_text,E' \r\n\t'))=0 THEN
  RAISE EXCEPTION 'a substantive current manuscript revision is required'
   USING ERRCODE='23514';
 END IF;

 SELECT count(*),count(r.revision_id),
  count(*) FILTER (WHERE r.revision_id IS NOT NULL
    AND length(btrim(r.body_text,E' \r\n\t'))>0),
  coalesce(jsonb_agg(jsonb_build_object(
   'unitId',u.unit_id,
   'kind',u.kind,
   'title',u.title,
   'position',u.display_position,
   'revisionId',r.revision_id,
   'revisionNumber',r.revision_number,
   'text',r.body_text)
   ORDER BY u.display_position,u.unit_id),'[]'::jsonb)
 INTO v_unit_count,v_revision_count,v_complete_count,v_units
 FROM atlas.teaching_course_units u
 LEFT JOIN LATERAL (
  SELECT q.revision_id,q.revision_number,q.body_text
  FROM atlas.teaching_course_unit_revisions q
  WHERE q.unit_id=u.unit_id
  ORDER BY q.revision_number DESC LIMIT 1
 ) r ON true
 WHERE u.course_id=v_course;
 IF v_unit_count<1 OR v_unit_count>100
 OR v_revision_count<>v_unit_count OR v_complete_count<>v_unit_count THEN
  RAISE EXCEPTION 'every ordered Course Unit must have substantive current revision'
   USING ERRCODE='23514';
 END IF;

 -- Capture exact saved composition under the same Course lock as material.
 -- A source without the composition reader cannot prepare a new edition.
 v_composition:=public.shared_teaching_course_composition_read_self_api_v1(v_course);
 IF v_composition->>'contractVersion' IS DISTINCT FROM 'shared_teaching_course_composition_v1'
 OR v_composition->>'courseId' IS DISTINCT FROM v_course::text
 OR jsonb_typeof(v_composition->'members') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'exact saved Class composition required' USING ERRCODE='42501'; END IF;
 -- Copy literal UTF-8 strings into immutable JSONB at this instant. Later
 -- edits or Unit moves on the live Course cannot rewrite sealed publication.
 v_payload:=jsonb_build_object(
   'format','shared_course_curriculum_snapshot_v1',
   'courseId',v_course,
   'courseVersionId',v_version.id,
   'versionNo',v_version.version_no,
   'definition',jsonb_build_object(
     'title',v_version.title,'summary',v_version.summary,
     'learningOutcomes',to_jsonb(v_version.learning_outcomes)),
   'manuscript',jsonb_build_object(
     'revisionId',v_manuscript.revision_id,
     'revisionNumber',v_manuscript.revision_number,
     'text',v_manuscript.body_text),
   'units',v_units,
   'composition',jsonb_build_object('revisionId',v_composition->'revisionId',
    'revisionNumber',v_composition->'revisionNumber','members',v_composition->'members')
 );
 INSERT INTO atlas.teaching_course_version_curriculum_snapshots(
   course_id,course_version_id,sealing_request_id,
   sealed_by_person_entity_id,curriculum_payload)
 VALUES(v_course,v_version.id,p_request_id,v_person,v_payload)
 RETURNING snapshot_id INTO v_snapshot_id;
 RETURN jsonb_build_object(
   'contractVersion','shared_course_curriculum_seal_v1',
   'courseId',v_course,'courseVersionId',v_version.id,
   'snapshotId',v_snapshot_id,'alreadyExists',false,
   'institutionCanRead',false,'canOpenOffering',false);
END $seal$;

-- The original author can privately inspect the sealed bytes and source
-- revision IDs even after Course retirement. No institution-specific reader.
CREATE FUNCTION public.shared_teaching_course_curriculum_snapshot_self_api_v1(
 p_course_version_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $private_read$
DECLARE
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
BEGIN
 IF p_course_version_id IS NULL THEN
  RAISE EXCEPTION 'authorized sealed Course Version required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_snapshot
 FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_version_id=p_course_version_id;
 IF v_snapshot.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'authorized sealed Course Version required'
   USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(v_snapshot.course_id,false);
 IF atlas.current_person_for_private_course_v1()
    IS DISTINCT FROM v_snapshot.sealed_by_person_entity_id THEN
  RAISE EXCEPTION 'original current Person author required'
   USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_curriculum_snapshot_private_v1',
  'courseId',v_snapshot.course_id,
  'courseVersionId',v_snapshot.course_version_id,
  'snapshotId',v_snapshot.snapshot_id,
  'sealedAt',v_snapshot.sealed_at,
  'curriculum',v_snapshot.curriculum_payload,
  'institutionCanRead',false,
  'canOpenOffering',false);
END $private_read$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)
 TO authenticated;
-- No public or operator curriculum read, publish/open transition, teacher
-- appointment, learner enrollment, student Work or descendant permissions.

-- SOURCE MODULE 4: candidates/shared-teaching-course-clean-cutover-v1/private_study_person_course_candidate.sql
-- HELD M3.17A — private author-to-learner Course study, no institution.
-- SOURCE CANDIDATE ONLY: network-isolated fictional PG17 / approved protected
-- clone. NEVER run on live Supabase, nor treat its availability as release.
-- One existing Person-origin Course; NO replacement Course, Ledger, Offering,
-- institutional Enrollment, Unit disclosure, classroom, homework, or Work.
-- Accepted offer is the Course-specific participation source, NOT a general
-- Reality Person-person relationship or automatic manuscript entitlement.
DO $private_study_gate$
BEGIN
 IF to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regclass('atlas.teaching_courses') IS NULL
 OR NOT EXISTS(SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name='teaching_courses'
     AND column_name='created_by_person_entity_id')
 THEN
  RAISE EXCEPTION 'held Person-first Course clone prerequisites required'
    USING ERRCODE='42501';
 END IF;
END $private_study_gate$;

-- Source owns one exact invitation to one existing canonical Person.
-- Request receipts and actor/source identity are immutable; one current
-- invitation per Course/learner pair until a later governed renewal rule.
CREATE TABLE atlas.teaching_course_private_study_invitations (
 invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 invited_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 invited_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz,
 UNIQUE(course_id,learner_person_entity_id),
 UNIQUE(invited_by_person_entity_id,request_id),
 CHECK(learner_person_entity_id<>invited_by_person_entity_id),
 CHECK(expires_at IS NULL OR expires_at>invited_at)
);
CREATE TABLE atlas.teaching_course_private_study_responses (
 response_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE
  REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('accept','decline')),
 responded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 responded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(responded_by_person_entity_id,request_id)
);
CREATE TABLE atlas.teaching_course_private_study_terminations (
 termination_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL UNIQUE
  REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 terminated_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 termination_kind text NOT NULL CHECK(termination_kind IN ('author_withdrew','learner_withdrew')),
 terminated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(terminated_by_person_entity_id,request_id)
);
ALTER TABLE atlas.teaching_course_private_study_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_study_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_study_terminations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_invitations FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_private_study_responses FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.teaching_course_private_study_terminations FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_private_study_original_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $$
BEGIN
 RAISE EXCEPTION 'private Course study receipts are immutable'
  USING ERRCODE='55000';
END $$;
CREATE TRIGGER private_study_invitation_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_invitations
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_study_response_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_responses
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_study_termination_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_terminations
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_private_study_original_mutation_v1()
 FROM PUBLIC,anon,authenticated;

-- Internal predicate: an independently accepted, nonterminated relationship.
-- This is a necessary input to later exact sealed Unit disclosure, not
-- sufficient permission to read any instruction. No public EXECUTE grant.
CREATE FUNCTION atlas.private_course_study_current_v1(
 p_course_id uuid,p_learner_person_entity_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog
AS $$
 SELECT p_course_id IS NOT NULL AND p_learner_person_entity_id IS NOT NULL
 AND EXISTS(
  SELECT 1 FROM atlas.teaching_course_private_study_invitations i
  JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
  JOIN reality.entities learner ON learner.id=i.learner_person_entity_id
    AND learner.entity_kind='person' AND learner.identity_state='canonical'
  JOIN reality.entities author ON author.id=i.invited_by_person_entity_id
    AND author.entity_kind='person' AND author.identity_state='canonical'
  JOIN atlas.teaching_course_private_study_responses r
    ON r.invitation_id=i.invitation_id AND r.decision='accept'
    AND r.responded_by_person_entity_id=i.learner_person_entity_id
  WHERE i.course_id=p_course_id
    AND i.learner_person_entity_id=p_learner_person_entity_id
    AND i.invited_by_person_entity_id=c.created_by_person_entity_id
    AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
      WHERE t.invitation_id=i.invitation_id)
 )
$$;
REVOKE ALL ON FUNCTION atlas.private_course_study_current_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

-- Exact Course author only. Course lock serializes invite minting with
-- author's Course status and same-Course idempotent request checks.
CREATE FUNCTION public.shared_teaching_private_study_invite_self_api_v1(
 p_course_id uuid,p_learner_person_entity_id uuid,
 p_request_id uuid,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $invite$
DECLARE
 v_person uuid;v_existing atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_invitation uuid;
BEGIN
 IF p_course_id IS NULL OR p_learner_person_entity_id IS NULL
 OR p_request_id IS NULL OR
 (p_expires_at IS NOT NULL AND p_expires_at<=clock_timestamp()) THEN
  RAISE EXCEPTION 'valid exact private study invitation required' USING ERRCODE='22023';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_learner_person_entity_id=v_person OR NOT EXISTS (
  SELECT 1 FROM reality.entities e
   WHERE e.id=p_learner_person_entity_id AND e.entity_kind='person'
    AND e.identity_state='canonical'
 ) THEN
  RAISE EXCEPTION 'known distinct canonical learner Person required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_existing FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invited_by_person_entity_id=v_person AND i.request_id=p_request_id;
 IF v_existing.invitation_id IS NOT NULL THEN
  IF v_existing.course_id IS DISTINCT FROM p_course_id
   OR v_existing.learner_person_entity_id IS DISTINCT FROM p_learner_person_entity_id
   OR v_existing.expires_at IS DISTINCT FROM p_expires_at THEN
   RAISE EXCEPTION 'changed immutable private study invitation request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_v1',
   'invitationId',v_existing.invitation_id,'alreadyExists',true,
   'consentAccepted',false,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF EXISTS(
  SELECT 1 FROM atlas.teaching_course_private_study_invitations i
   WHERE i.course_id=p_course_id
     AND i.learner_person_entity_id=p_learner_person_entity_id
 ) THEN
  RAISE EXCEPTION 'this Course/learner already has a study invitation'
   USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.teaching_course_private_study_invitations(
  course_id,learner_person_entity_id,invited_by_person_entity_id,
  request_id,expires_at
 ) VALUES (p_course_id,p_learner_person_entity_id,v_person,p_request_id,p_expires_at)
 RETURNING invitation_id INTO v_invitation;
 RETURN jsonb_build_object('contractVersion','private_course_study_v1',
  'invitationId',v_invitation,'alreadyExists',false,
  'consentAccepted',false,'canReadMaterial',false,'canSubmitWork',false);
END $invite$;

-- Only the invitee can inspect this one invitation. Title is disclosed
-- only in this explicitly targeted consent prompt; NO Unit or author notes.
CREATE FUNCTION public.shared_teaching_private_study_offer_read_self_api_v1(
 p_invitation_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $read_offer$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_title text;v_decision text;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv
 FROM atlas.teaching_course_private_study_invitations i
 JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
  AND c.created_by_person_entity_id=i.invited_by_person_entity_id
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person;
 IF v_inv.invitation_id IS NULL OR
 EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
    WHERE t.invitation_id=v_inv.invitation_id) THEN
  RAISE EXCEPTION 'known current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 SELECT r.decision INTO v_decision
 FROM atlas.teaching_course_private_study_responses r
 WHERE r.invitation_id=v_inv.invitation_id;
 IF v_decision IS NULL AND v_inv.expires_at IS NOT NULL
 AND v_inv.expires_at<=clock_timestamp() THEN
  RAISE EXCEPTION 'known current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 SELECT c.name INTO v_title FROM atlas.teaching_courses c
 WHERE c.id=v_inv.course_id;
 RETURN jsonb_build_object('contractVersion','private_course_study_offer_v1',
  'invitationId',v_inv.invitation_id,'courseTitle',v_title,
  'state',coalesce(v_decision,'offered'),
  'consentAccepted',coalesce(v_decision='accept',false),
  'canReadMaterial',false,'canSubmitWork',false);
END $read_offer$;

-- Exact learner signed Person; no author/parent/institution can accept
-- on their behalf. One terminal response, append-only and idempotent.
CREATE FUNCTION public.shared_teaching_private_study_respond_self_api_v1(
 p_invitation_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $respond$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_prev atlas.teaching_course_private_study_responses%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL
 OR p_decision IS NULL OR p_decision NOT IN ('accept','decline') THEN
  RAISE EXCEPTION 'exact signed study consent choice required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 JOIN atlas.teaching_courses c ON c.id=i.course_id AND c.status='active'
   AND c.created_by_person_entity_id=i.invited_by_person_entity_id
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person
 FOR UPDATE OF i;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'known current private study invitation required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prev FROM atlas.teaching_course_private_study_responses r
 WHERE r.invitation_id=v_inv.invitation_id;
 IF v_prev.response_id IS NOT NULL THEN
  IF v_prev.request_id IS DISTINCT FROM p_request_id
  OR v_prev.decision IS DISTINCT FROM p_decision
  OR v_prev.responded_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'private study consent is immutable'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_respond_v1',
   'invitationId',p_invitation_id,'decision',p_decision,
   'alreadyExists',true,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_terminations t
     WHERE t.invitation_id=v_inv.invitation_id)
 OR (v_inv.expires_at IS NOT NULL AND v_inv.expires_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'current private study invitation required'
  USING ERRCODE='42501'; END IF;
 INSERT INTO atlas.teaching_course_private_study_responses(
  invitation_id,request_id,decision,responded_by_person_entity_id
 ) VALUES(p_invitation_id,p_request_id,p_decision,v_person)
 RETURNING response_id INTO v_id;
 RETURN jsonb_build_object('contractVersion','private_course_study_respond_v1',
  'invitationId',p_invitation_id,'decision',p_decision,
  'alreadyExists',false,'canReadMaterial',false,'canSubmitWork',false);
END $respond$;

-- Withdrawal by the EXACT author or invited learner. A withdrawal is a
-- terminal original; no relationship can be revived by restoring UI state.
CREATE FUNCTION public.shared_teaching_private_study_withdraw_self_api_v1(
 p_invitation_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $withdraw$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_kind text;v_previous atlas.teaching_course_private_study_terminations%ROWTYPE;
BEGIN
 IF p_invitation_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact private study withdrawal required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 -- Check participant BEFORE locking private rows. Lock Course before
 -- invitation everywhere a Course-author mutation can race with invite.
 SELECT i.* INTO v_inv
 FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id
  AND v_person IN (i.learner_person_entity_id,i.invited_by_person_entity_id);
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'known current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 IF v_person=v_inv.invited_by_person_entity_id THEN
  PERFORM atlas.require_private_course_author_self_v1(v_inv.course_id,true);
  v_kind:='author_withdrew';
 ELSE
  PERFORM 1 FROM atlas.teaching_courses c
   WHERE c.id=v_inv.course_id AND c.status='active' FOR SHARE;
  IF NOT FOUND THEN
   RAISE EXCEPTION 'current private study Course required'
    USING ERRCODE='42501';
  END IF;
  v_kind:='learner_withdrew';
 END IF;
 SELECT i.* INTO v_inv
 FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id
  AND v_person IN (i.learner_person_entity_id,i.invited_by_person_entity_id)
 FOR UPDATE;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'current private study invitation required'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_previous FROM atlas.teaching_course_private_study_terminations t
 WHERE t.invitation_id=v_inv.invitation_id;
 IF v_previous.termination_id IS NOT NULL THEN
  IF v_previous.request_id IS DISTINCT FROM p_request_id
  OR v_previous.terminated_by_person_entity_id IS DISTINCT FROM v_person
  OR v_previous.termination_kind IS DISTINCT FROM v_kind THEN
   RAISE EXCEPTION 'private study withdrawal is terminal'
    USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('contractVersion','private_course_study_withdraw_v1',
   'invitationId',p_invitation_id,'alreadyExists',true,
   'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 INSERT INTO atlas.teaching_course_private_study_terminations(
  invitation_id,request_id,terminated_by_person_entity_id,termination_kind
 ) VALUES(p_invitation_id,p_request_id,v_person,v_kind);
 RETURN jsonb_build_object('contractVersion','private_course_study_withdraw_v1',
  'invitationId',p_invitation_id,'alreadyExists',false,
  'canReadMaterial',false,'canSubmitWork',false);
END $withdraw$;

-- Privileged data is never exposed directly. Each public entry point
-- re-resolves a *current signed* Person and enforces the exact actor.
REVOKE ALL ON FUNCTION
 public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz),
 public.shared_teaching_private_study_offer_read_self_api_v1(uuid),
 public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz),
 public.shared_teaching_private_study_offer_read_self_api_v1(uuid),
 public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text),
 public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)
 TO authenticated;
-- No lesson/version disclosure API defined here, NO student enrollment or Work.

-- SOURCE MODULE 5: candidates/shared-teaching-course-clean-cutover-v1/private_study_sealed_unit_candidate.sql
-- HELD M3.17B: independently authorized exact SEALED Unit edition to a
-- direct private-study learner of the SAME original Person-created Course.
-- This is a candidate for synthetic PG17 / owner-approved protected clone,
-- NEVER a production migration or permission release.
-- It depends on M3.17A current private study and M3.11 snapshot source.
-- No institutional Offering/Enrollment, no general manuscript/other Units,
-- no Notebook, submissions, Work, attendance, grading or Class operation.
DO $gate$
BEGIN
 IF to_regprocedure('atlas.private_course_study_current_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_invitations') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_responses') IS NULL
 OR to_regclass('atlas.teaching_course_private_study_terminations') IS NULL
 THEN RAISE EXCEPTION 'held original Course/private study/seal source required'
  USING ERRCODE='42501'; END IF;
END $gate$;

-- Later decisions on this SAME (invitation,Unit) are append-only: keep E1
-- after choosing E2, and WITHHOLD without mutating or erasing old receipts.
CREATE TABLE atlas.teaching_course_private_study_unit_decisions(
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 invitation_id uuid NOT NULL REFERENCES
  atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('allow','withhold')),
 course_version_id uuid REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
 snapshot_id uuid REFERENCES atlas.teaching_course_version_curriculum_snapshots(snapshot_id)
  ON DELETE RESTRICT,
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id)
  ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(decided_by_person_entity_id,request_id),
 UNIQUE(invitation_id,request_id),
 CHECK((decision='allow' AND course_version_id IS NOT NULL AND snapshot_id IS NOT NULL)
    OR (decision='withhold' AND course_version_id IS NULL AND snapshot_id IS NULL))
);
CREATE INDEX private_study_unit_latest_v1
 ON atlas.teaching_course_private_study_unit_decisions(invitation_id,unit_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_private_study_unit_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_unit_decisions
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.teaching_course_private_study_unit_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER private_study_unit_decision_immutable
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_study_unit_decisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Source-author decision is precisely tied to THIS invited learner and
-- ONE Unit in THIS SAME Course. A Version alone does not expose its text.
CREATE FUNCTION public.shared_teaching_private_study_unit_decide_self_api_v1(
 p_invitation_id uuid,p_unit_id uuid,p_request_id uuid,
 p_decision text,p_course_version_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $decide$
DECLARE
 v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_old atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_event bigint;v_snapshot_id uuid;
BEGIN
 IF p_invitation_id IS NULL OR p_unit_id IS NULL OR p_request_id IS NULL
 OR p_decision NOT IN ('allow','withhold')
 OR (p_decision='allow' AND p_course_version_id IS NULL)
 OR (p_decision='withhold' AND p_course_version_id IS NOT NULL)
 THEN RAISE EXCEPTION 'exact private Unit edition decision required'
  USING ERRCODE='22023'; END IF;
 -- Acquire Course lock first, consistent with author invitation/withdrawal.
 SELECT * INTO v_inv FROM atlas.teaching_course_private_study_invitations
 WHERE invitation_id=p_invitation_id;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'known private study original required' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(v_inv.course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF v_inv.invited_by_person_entity_id IS DISTINCT FROM v_person OR
 NOT EXISTS(SELECT 1 FROM atlas.teaching_course_units u
   WHERE u.unit_id=p_unit_id AND u.course_id=v_inv.course_id) THEN
  RAISE EXCEPTION 'exact authored study Unit required' USING ERRCODE='42501';
 END IF;
 -- Idempotent retries must remain valid, not rewrite original decision.
 SELECT * INTO v_old FROM atlas.teaching_course_private_study_unit_decisions
 WHERE decided_by_person_entity_id=v_person AND request_id=p_request_id;
 IF v_old.event_seq IS NOT NULL THEN
  IF v_old.invitation_id IS DISTINCT FROM p_invitation_id
  OR v_old.unit_id IS DISTINCT FROM p_unit_id
  OR v_old.decision IS DISTINCT FROM p_decision
  OR v_old.course_version_id IS DISTINCT FROM p_course_version_id THEN
   RAISE EXCEPTION 'changed private Unit decision replay' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object('contractVersion','private_study_unit_decision_v1',
   'invitationId',p_invitation_id,'unitId',p_unit_id,'decision',p_decision,
   'alreadyExists',true,'canReadMaterial',false,'canSubmitWork',false);
 END IF;
 IF p_decision='allow' THEN
  IF NOT atlas.private_course_study_current_v1(
    v_inv.course_id,v_inv.learner_person_entity_id) THEN
   RAISE EXCEPTION 'signed accepted private study required'
    USING ERRCODE='42501'; END IF;
  SELECT * INTO v_snapshot FROM atlas.teaching_course_version_curriculum_snapshots s
   WHERE s.course_id=v_inv.course_id
     AND s.course_version_id=p_course_version_id
     AND s.sealed_by_person_entity_id=v_person;
  IF v_snapshot.snapshot_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(
     v_snapshot.curriculum_payload->'units') q(unit)
    WHERE q.unit->>'unitId'=p_unit_id::text
      AND q.unit->>'revisionId' IS NOT NULL
      AND q.unit->>'text' IS NOT NULL
  ) THEN
   RAISE EXCEPTION 'original complete author-sealed Unit edition required'
    USING ERRCODE='42501';
  END IF;
  v_snapshot_id:=v_snapshot.snapshot_id;
 END IF;
 INSERT INTO atlas.teaching_course_private_study_unit_decisions(
  invitation_id,unit_id,request_id,decision,course_version_id,
  snapshot_id,decided_by_person_entity_id)
 VALUES(p_invitation_id,p_unit_id,p_request_id,p_decision,p_course_version_id,
  v_snapshot_id,v_person)
 RETURNING event_seq INTO v_event;
 RETURN jsonb_build_object('contractVersion','private_study_unit_decision_v1',
  'invitationId',p_invitation_id,'unitId',p_unit_id,'decision',p_decision,
  'eventSequence',v_event,'alreadyExists',false,
  'canReadMaterial',false,'canSubmitWork',false);
END $decide$;

-- Signed invitee reads exactly ONE author-released Unit, from the exact
-- immutable sealed Version selected for THIS Person + Unit. Inviting or
-- accepting alone NEVER provides a title or manuscript read here.
CREATE FUNCTION public.shared_teaching_private_study_sealed_unit_read_self_api_v1(
 p_invitation_id uuid,p_unit_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $read_one$
DECLARE
 v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_decision atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
 v_snap atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
 v_unit jsonb;
BEGIN
 IF p_invitation_id IS NULL OR p_unit_id IS NULL THEN
  RAISE EXCEPTION 'exact private study Unit required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id
  AND i.learner_person_entity_id=v_person;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'current own private study required' USING ERRCODE='42501';
 END IF;
 -- Course lock serializes with author issue and retirement, then invitation
 -- lock serializes with withdrawal; readers never depend on browser-role tags.
 PERFORM 1 FROM atlas.teaching_courses c
  WHERE c.id=v_inv.course_id AND c.status='active'
    AND c.created_by_person_entity_id=v_inv.invited_by_person_entity_id
  FOR SHARE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'current exact Course required' USING ERRCODE='42501';
 END IF;
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
  WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person
  FOR SHARE;
 IF v_inv.invitation_id IS NULL OR NOT atlas.private_course_study_current_v1(
  v_inv.course_id,v_person) THEN
  RAISE EXCEPTION 'current signed accepted study required' USING ERRCODE='42501';
 END IF;
 SELECT d.* INTO v_decision FROM atlas.teaching_course_private_study_unit_decisions d
 WHERE d.invitation_id=v_inv.invitation_id AND d.unit_id=p_unit_id
 ORDER BY d.event_seq DESC LIMIT 1;
 IF v_decision.event_seq IS NULL OR v_decision.decision<>'allow' THEN
  RAISE EXCEPTION 'exact author-released Unit unavailable' USING ERRCODE='42501';
 END IF;
 SELECT s.* INTO v_snap FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.snapshot_id=v_decision.snapshot_id AND s.course_id=v_inv.course_id
  AND s.course_version_id=v_decision.course_version_id
  AND s.sealed_by_person_entity_id=v_inv.invited_by_person_entity_id;
 IF v_snap.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'original immutable Unit edition unavailable' USING ERRCODE='42501';
 END IF;
 SELECT q.unit INTO v_unit FROM jsonb_array_elements(
  v_snap.curriculum_payload->'units') q(unit)
 WHERE q.unit->>'unitId'=p_unit_id::text;
 IF v_unit IS NULL THEN
  RAISE EXCEPTION 'exact sealed Unit unavailable' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('contractVersion','private_study_sealed_unit_read_v1',
  'invitationId',v_inv.invitation_id,
  'courseId',v_inv.course_id,'courseVersionId',v_snap.course_version_id,
  'unitId',p_unit_id,'snapshotId',v_snap.snapshot_id,
  'unit',jsonb_build_object(
    'unitId',p_unit_id,'kind',v_unit->'kind','title',v_unit->'title',
    'position',v_unit->'position',
    'revisionId',v_unit->'revisionId',
    'revisionNumber',v_unit->'revisionNumber','text',v_unit->'text'),
  'canReadOtherUnits',false,'canReadManuscript',false,
  'canReadCurriculum',false,'canSubmitWork',false,'canTeach',false);
END $read_one$;
REVOKE ALL ON FUNCTION
 public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid),
 public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid),
 public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)
 TO authenticated;
-- Complete a separately governed student source (notes, submissions,
-- feedback and encounter history) BEFORE claiming functional classroom.

-- T5b: metadata-only index of the exact currently issued Units, not curriculum
-- disclosure. Reuse the one-Unit reader's authority and immutable edition.
CREATE FUNCTION public.shared_teaching_private_study_index_self_api_v1(p_invitation_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $index$
DECLARE v_person uuid;v_inv atlas.teaching_course_private_study_invitations%ROWTYPE;
 v_unit_id uuid;v_record jsonb;v_items jsonb:='[]'::jsonb;v_count integer:=0;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person;
 IF v_inv.invitation_id IS NULL THEN
  RAISE EXCEPTION 'current own private study required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.teaching_courses c WHERE c.id=v_inv.course_id AND c.status='active'
  AND c.created_by_person_entity_id=v_inv.invited_by_person_entity_id FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'current exact Course required' USING ERRCODE='42501'; END IF;
 SELECT i.* INTO v_inv FROM atlas.teaching_course_private_study_invitations i
 WHERE i.invitation_id=p_invitation_id AND i.learner_person_entity_id=v_person FOR SHARE;
 IF v_inv.invitation_id IS NULL OR NOT atlas.private_course_study_current_v1(v_inv.course_id,v_person)
 THEN RAISE EXCEPTION 'current signed accepted study required' USING ERRCODE='42501'; END IF;
 FOR v_unit_id IN SELECT latest.unit_id FROM (
   SELECT DISTINCT ON(d.unit_id) d.unit_id,d.decision FROM atlas.teaching_course_private_study_unit_decisions d
   WHERE d.invitation_id=p_invitation_id ORDER BY d.unit_id,d.event_seq DESC
  ) latest WHERE latest.decision='allow' ORDER BY latest.unit_id LIMIT 101
 LOOP
  v_count:=v_count+1;
  IF v_count>100 THEN RAISE EXCEPTION 'issued study index exceeds bounded view' USING ERRCODE='54000'; END IF;
  v_record:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(p_invitation_id,v_unit_id);
  v_items:=v_items||jsonb_build_array(jsonb_build_object(
   'unitId',v_record->'unitId','courseVersionId',v_record->'courseVersionId',
   'snapshotId',v_record->'snapshotId','revisionId',v_record->'unit'->'revisionId',
   'title',v_record->'unit'->'title','kind',v_record->'unit'->'kind',
   'position',v_record->'unit'->'position'));
 END LOOP;
 -- Only reveal membership when both exact Units were issued from the
 -- SAME immutable snapshot. Older seals without composition stay flat.
 SELECT coalesce(jsonb_agg(x.item||jsonb_build_object(
  'classUnitId',m.member->'classUnitId','depth',m.member->'depth')
  ORDER BY (x.item->>'position')::integer,x.item->>'unitId'),'[]'::jsonb)
 INTO v_items FROM jsonb_array_elements(v_items) x(item)
 JOIN atlas.teaching_course_version_curriculum_snapshots s
  ON s.snapshot_id=(x.item->>'snapshotId')::uuid AND s.course_id=v_inv.course_id
 LEFT JOIN LATERAL (
  SELECT q.member FROM jsonb_array_elements(coalesce(s.curriculum_payload->'composition'->'members','[]'::jsonb)) q(member)
  WHERE q.member->>'unitId'=x.item->>'unitId'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_items) parent(item)
   WHERE parent.item->>'unitId'=q.member->>'classUnitId'
   AND parent.item->>'snapshotId'=x.item->>'snapshotId' AND parent.item->>'kind'='lesson')
 ) m ON true;
 RETURN jsonb_build_object('contractVersion','private_study_issued_index_v1',
  'invitationId',p_invitation_id,'courseId',v_inv.course_id,'units',v_items,
  'canReadCurriculum',false,'canReadManuscript',false);
END $index$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_study_index_self_api_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_study_index_self_api_v1(uuid) TO authenticated;

-- T5c: the existing original author's private delivery register. No Person
-- directory, new recipient identity, learner Notebook, or public publication.
CREATE FUNCTION public.shared_teaching_private_study_delivery_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $delivery$
DECLARE v_person uuid;v_course uuid;v_invites jsonb;v_editions jsonb;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF (SELECT count(*) FROM atlas.teaching_course_private_study_invitations i
 WHERE i.course_id=v_course AND i.invited_by_person_entity_id=v_person)>100
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_id=v_course AND s.sealed_by_person_entity_id=v_person)>100
 THEN RAISE EXCEPTION 'delivery register exceeds bounded view' USING ERRCODE='54000';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'invitationId',i.invitation_id,'learnerPersonId',i.learner_person_entity_id,
  'state',CASE WHEN t.termination_id IS NOT NULL THEN 'withdrawn'
   WHEN r.decision IS NOT NULL THEN r.decision
   WHEN i.expires_at IS NOT NULL AND i.expires_at<=clock_timestamp() THEN 'expired' ELSE 'offered' END,
  'issued',coalesce((SELECT jsonb_agg(jsonb_build_object('unitId',d.unit_id,'courseVersionId',d.course_version_id,
    'snapshotId',d.snapshot_id) ORDER BY d.unit_id) FROM (
    SELECT DISTINCT ON(u.unit_id) u.unit_id,u.course_version_id,u.snapshot_id,u.decision
    FROM atlas.teaching_course_private_study_unit_decisions u WHERE u.invitation_id=i.invitation_id
    ORDER BY u.unit_id,u.event_seq DESC) d WHERE d.decision='allow' AND t.termination_id IS NULL),'[]'::jsonb))
  ORDER BY i.invited_at,i.invitation_id),'[]'::jsonb) INTO v_invites
 FROM atlas.teaching_course_private_study_invitations i
 LEFT JOIN atlas.teaching_course_private_study_responses r ON r.invitation_id=i.invitation_id
 LEFT JOIN atlas.teaching_course_private_study_terminations t ON t.invitation_id=i.invitation_id
 WHERE i.course_id=v_course AND i.invited_by_person_entity_id=v_person;
 SELECT coalesce(jsonb_agg(jsonb_build_object('courseVersionId',s.course_version_id,
  'snapshotId',s.snapshot_id,'title',v.title,'versionNo',v.version_no,
  'units',(SELECT coalesce(jsonb_agg(jsonb_build_object('unitId',u.item->'unitId',
   'title',u.item->'title','kind',u.item->'kind','position',u.item->'position',
   'revisionId',u.item->'revisionId','revisionNumber',u.item->'revisionNumber')
   ORDER BY (u.item->>'position')::integer,u.item->>'unitId'),'[]'::jsonb)
   FROM jsonb_array_elements(s.curriculum_payload->'units') u(item)))
  ORDER BY v.version_no),'[]'::jsonb) INTO v_editions
 FROM atlas.teaching_course_version_curriculum_snapshots s
 JOIN atlas.teaching_course_versions v ON v.id=s.course_version_id AND v.course_id=s.course_id
 WHERE s.course_id=v_course AND s.sealed_by_person_entity_id=v_person;
 RETURN jsonb_build_object('contractVersion','private_study_delivery_v1','courseId',v_course,
  'invitations',v_invites,'editions',v_editions,'publicPublication',false);
END $delivery$;

-- Atomically prepare a private edition from saved originals using the existing
-- immutable definition+seal operations. No learner is issued anything here.
CREATE FUNCTION public.shared_teaching_private_study_prepare_edition_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_title text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $prepare$
DECLARE v_definition jsonb;v_seal jsonb;
BEGIN
 v_definition:=public.shared_teaching_course_definition_publish_self_api_v1(
  p_course_id,p_request_id,p_title,NULL,ARRAY[]::text[]);
 v_seal:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  p_course_id,(v_definition->>'courseVersionId')::uuid,p_request_id);
 RETURN jsonb_build_object('contractVersion','private_study_prepared_edition_v1',
  'courseId',p_course_id,'courseVersionId',v_seal->'courseVersionId','snapshotId',v_seal->'snapshotId',
  'alreadyExists',v_seal->'alreadyExists','publicPublication',false);
END $prepare$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_study_delivery_self_api_v1(uuid),
 public.shared_teaching_private_study_prepare_edition_self_api_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_study_delivery_self_api_v1(uuid),
 public.shared_teaching_private_study_prepare_edition_self_api_v1(uuid,uuid,text) TO authenticated;

-- SOURCE MODULE 6: candidates/shared-teaching-course-clean-cutover-v1/private_study_answer_candidate.sql
-- HELD M3.17C: private student answer originals on the existing direct-study
-- sealed Unit. No submission, teacher read, issuance, grading or learner seed.
DO $gate$
BEGIN
 IF to_regprocedure('public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held sealed private study prerequisite' USING ERRCODE='42501'; END IF;
END $gate$;

CREATE TABLE atlas.teaching_course_private_study_answer_revisions(
 answer_revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 snapshot_id uuid NOT NULL REFERENCES atlas.teaching_course_version_curriculum_snapshots(snapshot_id) ON DELETE RESTRICT,
 unit_revision_id uuid NOT NULL REFERENCES atlas.teaching_course_unit_revisions(revision_id) ON DELETE RESTRICT,
 activity_id uuid NOT NULL,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK(based_on_revision BETWEEN 0 AND 9999),
 revision_no integer NOT NULL CHECK(revision_no=based_on_revision+1),
 body_text text NOT NULL CHECK(char_length(body_text) BETWEEN 1 AND 20000 AND btrim(body_text)<>''),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(invitation_id,unit_id,snapshot_id,unit_revision_id,activity_id,revision_no),
 UNIQUE(learner_person_entity_id,request_id)
);
ALTER TABLE atlas.teaching_course_private_study_answer_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_answer_revisions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER private_answer_immutable BEFORE UPDATE OR DELETE
 ON atlas.teaching_course_private_study_answer_revisions FOR EACH ROW
 EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_answer_no_truncate BEFORE TRUNCATE
 ON atlas.teaching_course_private_study_answer_revisions FOR EACH STATEMENT
 EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Conservative shared text grammar: explicit top-level UUIDv4 Question, a
-- unique marker, and a nonempty first ordinary paragraph. No code or
-- presentation block can create an answerable question. More complex source
-- is deliberately refused rather than guessed. No title/ordinal identity.
CREATE FUNCTION atlas.private_study_question_valid_v1(p_text text,p_activity uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO pg_catalog AS $$
DECLARE lines text[];i integer;line text;marker text;hits integer:=0;found boolean:=false;
 disclosure boolean:=false;fence text:=NULL;j integer;
BEGIN
 IF p_text IS NULL OR p_activity IS NULL OR p_activity::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN RETURN false; END IF;
 marker:=' {#titus-activity:'||p_activity::text||'}';
 lines:=string_to_array(replace(replace(p_text,E'\r\n',E'\n'),E'\r',E'\n'),E'\n');
 FOR i IN 1..coalesce(array_length(lines,1),0) LOOP
  line:=lines[i];
  -- Count even malformed duplicates; refuse ambiguous marker anywhere.
  IF strpos(lower(line),marker)>0 THEN hits:=hits+1;
   IF strpos(substring(lower(line) FROM strpos(lower(line),marker)+length(marker)),marker)>0 THEN RETURN false; END IF;
  END IF;
  IF line ~ '^ {0,3}(\x60{3,}|~{3,})' THEN
   IF fence IS NULL THEN fence:=left(ltrim(line),1);
   ELSIF left(ltrim(line),1)=fence THEN fence:=NULL; END IF;
   CONTINUE;
  END IF;
  IF fence IS NOT NULL THEN CONTINUE; END IF;
  IF line ~ '^:::(scripture|evidence|reveal) ' THEN
   IF disclosure THEN RETURN false; END IF;
   disclosure:=true;CONTINUE;
  END IF;
  IF line=':::' THEN disclosure:=false;CONTINUE; END IF;
  IF disclosure THEN CONTINUE; END IF;
  IF lower(line)='## question'||marker THEN
   j:=i+1;
   WHILE j<=array_length(lines,1) AND btrim(lines[j])='' LOOP j:=j+1; END LOOP;
   IF j>array_length(lines,1) OR lines[j] ~ '^\s*(#|>|[-*] |\d+\. |\||:::|\x60{3,}|~{3,})' THEN RETURN false; END IF;
   found:=true;
  END IF;
 END LOOP;
 RETURN found AND hits=1 AND NOT disclosure AND fence IS NULL;
END $$;
REVOKE ALL ON FUNCTION atlas.private_study_question_valid_v1(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Reuse the exact existing signed learner, Course lock, invitation lock,
-- accepted relation and current author-released sealed Unit check. A private
-- write is learner-origin only and never changes the source or discloses it.
CREATE FUNCTION atlas.private_study_answer_scope_self_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE j jsonb;v_person uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(p_invitation,p_unit);
 IF j->>'contractVersion' IS DISTINCT FROM 'private_study_sealed_unit_read_v1'
 OR j->>'snapshotId' IS DISTINCT FROM p_snapshot::text
 OR j->'unit'->>'revisionId' IS DISTINCT FROM p_unit_revision::text
 OR NOT atlas.private_study_question_valid_v1(j->'unit'->>'text',p_activity)
 THEN RAISE EXCEPTION 'current exact issued question unavailable' USING ERRCODE='42501'; END IF;
 RETURN v_person;
END $$;
REVOKE ALL ON FUNCTION atlas.private_study_answer_scope_self_v1(uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION atlas.private_study_answer_receipt_v1(r atlas.teaching_course_private_study_answer_revisions)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog AS $$
 SELECT jsonb_build_object('contractVersion','private_study_answer_v1','invitationId',r.invitation_id,
 'unitId',r.unit_id,'snapshotId',r.snapshot_id,'unitRevisionId',r.unit_revision_id,
 'activityId',r.activity_id,'answerRevisionId',r.answer_revision_id,'revisionNumber',r.revision_no,
 'requestId',r.request_id,'text',r.body_text,'savedAt',r.recorded_at,'private',true,'submitted',false)
$$;
REVOKE ALL ON FUNCTION atlas.private_study_answer_receipt_v1(atlas.teaching_course_private_study_answer_revisions) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;r atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
BEGIN
 v_person:=atlas.private_study_answer_scope_self_v1(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity);
 SELECT * INTO r FROM atlas.teaching_course_private_study_answer_revisions a
 WHERE a.invitation_id=p_invitation AND a.unit_id=p_unit AND a.snapshot_id=p_snapshot
 AND a.unit_revision_id=p_unit_revision AND a.activity_id=p_activity AND a.learner_person_entity_id=v_person
 ORDER BY a.revision_no DESC LIMIT 1;
 IF r.answer_revision_id IS NULL THEN
  RETURN jsonb_build_object('contractVersion','private_study_answer_v1','invitationId',p_invitation,
   'unitId',p_unit,'snapshotId',p_snapshot,'unitRevisionId',p_unit_revision,'activityId',p_activity,
   'answerRevisionId',NULL,'revisionNumber',0,'requestId',NULL,'text',NULL,'savedAt',NULL,'private',true,'submitted',false);
 END IF;
 RETURN atlas.private_study_answer_receipt_v1(r);
END $$;
CREATE FUNCTION public.shared_teaching_private_study_answer_save_self_api_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid,
 p_request uuid,p_expected_revision integer,p_text text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;r atlas.teaching_course_private_study_answer_revisions%ROWTYPE;n integer;
BEGIN
 IF p_request IS NULL OR p_expected_revision IS NULL OR p_expected_revision NOT BETWEEN 0 AND 9999
 OR p_text IS NULL OR char_length(p_text) NOT BETWEEN 1 AND 20000 OR btrim(p_text)=''
 THEN RAISE EXCEPTION 'invalid answer revision' USING ERRCODE='22023'; END IF;
 v_person:=atlas.private_study_answer_scope_self_v1(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity);
 -- The existing source acquired Course/invitation shared locks; do not
 -- upgrade them. Serialize only this answer thread after authorization.
 PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws(':',p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity),0));
 SELECT * INTO r FROM atlas.teaching_course_private_study_answer_revisions
 WHERE learner_person_entity_id=v_person AND request_id=p_request;
 IF r.answer_revision_id IS NOT NULL THEN
  IF r.invitation_id IS DISTINCT FROM p_invitation OR r.unit_id IS DISTINCT FROM p_unit
  OR r.snapshot_id IS DISTINCT FROM p_snapshot OR r.unit_revision_id IS DISTINCT FROM p_unit_revision
  OR r.activity_id IS DISTINCT FROM p_activity OR r.based_on_revision IS DISTINCT FROM p_expected_revision
  OR r.body_text IS DISTINCT FROM p_text OR r.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
  THEN RAISE EXCEPTION 'changed answer request' USING ERRCODE='23505'; END IF;
  RETURN atlas.private_study_answer_receipt_v1(r);
 END IF;
 SELECT coalesce(max(revision_no),0) INTO n FROM atlas.teaching_course_private_study_answer_revisions
 WHERE invitation_id=p_invitation AND unit_id=p_unit AND snapshot_id=p_snapshot
 AND unit_revision_id=p_unit_revision AND activity_id=p_activity AND learner_person_entity_id=v_person;
 IF n<>p_expected_revision THEN RAISE EXCEPTION 'stale answer revision' USING ERRCODE='40001'; END IF;
 INSERT INTO atlas.teaching_course_private_study_answer_revisions(invitation_id,unit_id,snapshot_id,unit_revision_id,activity_id,
 learner_person_entity_id,recorded_by_auth_user_id,request_id,based_on_revision,revision_no,body_text)
 VALUES(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity,v_person,auth.uid(),p_request,n,n+1,p_text)
 RETURNING * INTO r;
 RETURN atlas.private_study_answer_receipt_v1(r);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid),
 public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid),
 public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)
 TO authenticated;

-- SOURCE MODULE 7: candidates/shared-teaching-course-clean-cutover-v1/private_study_submission_candidate.sql
-- HELD M3.17D: one explicit learner submission and direct author review.
-- No institution, publication, enrollment, generic Notebook reader or grade.
DO $gate$
BEGIN
 IF to_regclass('atlas.teaching_course_private_study_answer_revisions') IS NULL
 OR to_regprocedure('atlas.private_study_answer_scope_self_v1(uuid,uuid,uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'held private answer source required' USING ERRCODE='42501'; END IF;
END $gate$;
CREATE TABLE atlas.teaching_course_private_answer_submissions(
 submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 answer_revision_id uuid NOT NULL UNIQUE REFERENCES atlas.teaching_course_private_study_answer_revisions(answer_revision_id) ON DELETE RESTRICT,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(learner_person_entity_id,request_id),
 CHECK(learner_person_entity_id<>reviewer_person_entity_id)
);
CREATE TABLE atlas.teaching_course_private_answer_review_events(
 event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 submission_id uuid NOT NULL REFERENCES atlas.teaching_course_private_answer_submissions(submission_id) ON DELETE RESTRICT,
 event_kind text NOT NULL CHECK(event_kind IN ('accept_review','withdraw','feedback')),
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 feedback_text text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(submission_id,event_kind),UNIQUE(actor_person_entity_id,request_id),
 CHECK((event_kind='feedback' AND feedback_text IS NOT NULL AND char_length(feedback_text) BETWEEN 1 AND 20000 AND btrim(feedback_text,E' \r\n\t')<>'')
 OR (event_kind<>'feedback' AND feedback_text IS NULL))
);
ALTER TABLE atlas.teaching_course_private_answer_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_answer_review_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_answer_submissions,atlas.teaching_course_private_answer_review_events FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER private_submission_immutable BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_answer_submissions FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_submission_no_truncate BEFORE TRUNCATE ON atlas.teaching_course_private_answer_submissions FOR EACH STATEMENT EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_review_event_immutable BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_answer_review_events FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_review_event_no_truncate BEFORE TRUNCATE ON atlas.teaching_course_private_answer_review_events FOR EACH STATEMENT EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Teacher standing is the current direct-study original Course author, not a
-- role name or client flag. Exact consent AND independent reviewer acceptance
-- are still required to disclose even the selected answer text.
CREATE FUNCTION atlas.private_answer_reviewer_current_v1(
 a atlas.teaching_course_private_study_answer_revisions,p_reviewer uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE i atlas.teaching_course_private_study_invitations%ROWTYPE;
 d atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
BEGIN
 SELECT * INTO i FROM atlas.teaching_course_private_study_invitations
 WHERE invitation_id=a.invitation_id AND invited_by_person_entity_id=p_reviewer
 AND learner_person_entity_id=a.learner_person_entity_id;
 IF i.invitation_id IS NULL THEN RAISE EXCEPTION 'exact named reviewer required' USING ERRCODE='42501'; END IF;
 -- Same lock order as existing author release/withdrawal. Require current
 -- author write access even for review read in this narrow held contract.
 PERFORM atlas.require_private_course_author_self_v1(i.course_id,true);
 PERFORM 1 FROM atlas.teaching_course_private_study_invitations WHERE invitation_id=i.invitation_id FOR SHARE;
 IF NOT atlas.private_course_study_current_v1(i.course_id,i.learner_person_entity_id)
 THEN RAISE EXCEPTION 'current accepted direct study required' USING ERRCODE='42501'; END IF;
 SELECT * INTO d FROM atlas.teaching_course_private_study_unit_decisions
 WHERE invitation_id=i.invitation_id AND unit_id=a.unit_id ORDER BY event_seq DESC LIMIT 1;
 IF d.decision IS DISTINCT FROM 'allow' OR d.snapshot_id IS DISTINCT FROM a.snapshot_id
 THEN RAISE EXCEPTION 'current released answer edition required' USING ERRCODE='42501'; END IF;
END $$;
REVOKE ALL ON FUNCTION atlas.private_answer_reviewer_current_v1(atlas.teaching_course_private_study_answer_revisions,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(
 p_answer_revision_id uuid,p_reviewer_person_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 s atlas.teaching_course_private_answer_submissions%ROWTYPE;
BEGIN
 IF p_answer_revision_id IS NULL OR p_reviewer_person_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'select saved revision and named reviewer explicitly' USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=p_answer_revision_id AND learner_person_entity_id=v_person;
 IF a.answer_revision_id IS NULL THEN RAISE EXCEPTION 'own saved revision required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_invitations i WHERE i.invitation_id=a.invitation_id
 AND i.invited_by_person_entity_id=p_reviewer_person_id AND i.learner_person_entity_id=v_person)
 THEN RAISE EXCEPTION 'reviewer must be the actual direct-study author' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(a.answer_revision_id::text,1));
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE learner_person_entity_id=v_person AND request_id=p_request_id;
 IF s.submission_id IS NOT NULL THEN
  IF s.answer_revision_id IS DISTINCT FROM a.answer_revision_id OR s.reviewer_person_entity_id IS DISTINCT FROM p_reviewer_person_id OR s.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
   THEN RAISE EXCEPTION 'changed submission request' USING ERRCODE='23505'; END IF;
 ELSE
  INSERT INTO atlas.teaching_course_private_answer_submissions(answer_revision_id,learner_person_entity_id,reviewer_person_entity_id,request_id,recorded_by_auth_user_id)
  VALUES(a.answer_revision_id,v_person,p_reviewer_person_id,p_request_id,auth.uid()) RETURNING * INTO s;
 END IF;
 RETURN jsonb_build_object('contractVersion','private_answer_submission_v1','submissionId',s.submission_id,
 'answerRevisionId',s.answer_revision_id,'reviewerPersonId',s.reviewer_person_entity_id,'requestId',s.request_id,
 'submittedAt',s.recorded_at,'purpose','review_selected_answer','notebookDisclosed',false);
END $$;

-- Own learner or exact named reviewer. Locks the original Course, invitation,
-- then submission. All later decisions serialize on this SAME row.
CREATE FUNCTION atlas.private_answer_submission_scope_v1(p_submission uuid,p_mode text)
RETURNS atlas.teaching_course_private_answer_submissions LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;s atlas.teaching_course_private_answer_submissions%ROWTYPE;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE submission_id=p_submission
 AND ((p_mode='learner' AND learner_person_entity_id=v_person) OR (p_mode='reviewer' AND reviewer_person_entity_id=v_person));
 IF s.submission_id IS NULL THEN RAISE EXCEPTION 'own selected submission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=s.answer_revision_id;
 IF p_mode='learner' THEN
  PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 ELSE PERFORM atlas.private_answer_reviewer_current_v1(a,v_person); END IF;
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE submission_id=p_submission FOR UPDATE;
 RETURN s;
END $$;
REVOKE ALL ON FUNCTION atlas.private_answer_submission_scope_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_answer_review_event_self_api_v1(
 p_submission_id uuid,p_request_id uuid,p_action text,p_feedback text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE s atlas.teaching_course_private_answer_submissions%ROWTYPE;e atlas.teaching_course_private_answer_review_events%ROWTYPE;v_person uuid;
BEGIN
 IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('accept_review','withdraw','feedback')
 OR (p_action='feedback' AND (p_feedback IS NULL OR char_length(p_feedback) NOT BETWEEN 1 AND 20000 OR btrim(p_feedback,E' \r\n\t')=''))
 OR (p_action<>'feedback' AND p_feedback IS NOT NULL)
 THEN RAISE EXCEPTION 'explicit valid review action required' USING ERRCODE='22023'; END IF;
 s:=atlas.private_answer_submission_scope_v1(p_submission_id,CASE WHEN p_action='withdraw' THEN 'learner' ELSE 'reviewer' END);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO e FROM atlas.teaching_course_private_answer_review_events WHERE actor_person_entity_id=v_person AND request_id=p_request_id;
 IF e.event_id IS NOT NULL THEN
  IF e.submission_id IS DISTINCT FROM s.submission_id OR e.event_kind IS DISTINCT FROM p_action OR e.feedback_text IS DISTINCT FROM p_feedback OR e.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
   THEN RAISE EXCEPTION 'changed review request' USING ERRCODE='23505'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='withdraw')
  THEN RAISE EXCEPTION 'submission withdrawn' USING ERRCODE='42501'; END IF;
  IF p_action='feedback' AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='accept_review' AND actor_person_entity_id=v_person)
  THEN RAISE EXCEPTION 'independent reviewer acceptance required' USING ERRCODE='42501'; END IF;
  INSERT INTO atlas.teaching_course_private_answer_review_events(submission_id,event_kind,actor_person_entity_id,recorded_by_auth_user_id,request_id,feedback_text)
  VALUES(s.submission_id,p_action,v_person,auth.uid(),p_request_id,p_feedback) RETURNING * INTO e;
 END IF;
 RETURN jsonb_build_object('contractVersion','private_answer_review_event_v1','submissionId',s.submission_id,
 'eventId',e.event_id,'action',e.event_kind,'requestId',e.request_id,'recordedAt',e.recorded_at);
END $$;

-- The reviewer may inspect a bounded submission header before acceptance,
-- but receives no answer, prompt text, other revision, private notes or list.
-- After withdrawal reviewer gets no contents. Own learner read remains gated
-- by current encounter; retained-history policy is not decided here.
CREATE FUNCTION public.shared_teaching_private_answer_submission_read_self_api_v1(
 p_submission_id uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE s atlas.teaching_course_private_answer_submissions%ROWTYPE;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 f atlas.teaching_course_private_answer_review_events%ROWTYPE;accepted boolean;withdrawn boolean;
BEGIN
 IF p_mode IS NULL OR p_mode NOT IN ('learner','reviewer') THEN RAISE EXCEPTION 'exact participant mode required' USING ERRCODE='22023'; END IF;
 s:=atlas.private_answer_submission_scope_v1(p_submission_id,p_mode);
 SELECT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='withdraw'),
 EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='accept_review' AND actor_person_entity_id=s.reviewer_person_entity_id)
 INTO withdrawn,accepted;
 IF p_mode='reviewer' AND withdrawn THEN RAISE EXCEPTION 'submission withdrawn' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=s.answer_revision_id;
 SELECT * INTO f FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='feedback' AND actor_person_entity_id=s.reviewer_person_entity_id;
 RETURN jsonb_build_object('contractVersion','private_answer_submission_read_v1','submissionId',s.submission_id,
 'answerRevisionId',a.answer_revision_id,'invitationId',a.invitation_id,'unitId',a.unit_id,'snapshotId',a.snapshot_id,
 'unitRevisionId',a.unit_revision_id,'activityId',a.activity_id,'revisionNumber',a.revision_no,
 'reviewerPersonId',s.reviewer_person_entity_id,'state',CASE WHEN withdrawn THEN 'withdrawn' WHEN f.event_id IS NOT NULL THEN 'feedback' WHEN accepted THEN 'accepted' ELSE 'submitted' END,
 'text',CASE WHEN p_mode='learner' OR accepted THEN a.body_text ELSE NULL END,
 'feedback',CASE WHEN f.event_id IS NULL THEN NULL ELSE jsonb_build_object('eventId',f.event_id,'text',f.feedback_text,'recordedAt',f.recorded_at) END,
 'notebookDisclosed',false);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text) TO authenticated;

-- Own-answer entry point: derive the only direct reviewer from the source,
-- never from an entered person name. No automatic submission.
CREATE FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(p_answer_revision_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 reviewer uuid;s_id uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions
 WHERE answer_revision_id=p_answer_revision_id AND learner_person_entity_id=v_person;
 IF a.answer_revision_id IS NULL THEN RAISE EXCEPTION 'own answer required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 SELECT invited_by_person_entity_id INTO reviewer FROM atlas.teaching_course_private_study_invitations WHERE invitation_id=a.invitation_id;
 SELECT submission_id INTO s_id FROM atlas.teaching_course_private_answer_submissions WHERE answer_revision_id=a.answer_revision_id;
 RETURN jsonb_build_object('contractVersion','private_answer_review_target_v1','answerRevisionId',a.answer_revision_id,
 'reviewerPersonId',reviewer,'submissionId',s_id,'purpose','review_selected_answer');
END $$;
-- Bounded author inbox: only consented submissions for this original Course
-- with current exact issued relationship, including submitted headers prior
-- to review acceptance. No answer text, private revisions, unrelated records
-- or roster. Cursor is on the immutable submission ordering.
CREATE FUNCTION public.shared_teaching_private_answer_review_inbox_self_api_v1(p_course_id uuid,p_before uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_course uuid;v_person uuid;v_before_at timestamptz;items jsonb;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_before IS NOT NULL THEN
  SELECT s.recorded_at INTO v_before_at FROM atlas.teaching_course_private_answer_submissions s
  JOIN atlas.teaching_course_private_study_answer_revisions a ON a.answer_revision_id=s.answer_revision_id
  JOIN atlas.teaching_course_private_study_invitations i ON i.invitation_id=a.invitation_id
  WHERE s.submission_id=p_before AND s.reviewer_person_entity_id=v_person AND i.course_id=v_course;
  IF v_before_at IS NULL THEN RAISE EXCEPTION 'invalid inbox cursor' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('submissionId',q.submission_id,'answerRevisionId',q.answer_revision_id,
 'unitId',q.unit_id,'activityId',q.activity_id,'revisionNumber',q.revision_no,'recordedAt',q.recorded_at,'state',q.state)
 ORDER BY q.recorded_at DESC,q.submission_id DESC),'[]'::jsonb) INTO items FROM (
 SELECT s.submission_id,s.answer_revision_id,s.recorded_at,a.unit_id,a.activity_id,a.revision_no,
 CASE WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='feedback') THEN 'feedback'
 WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='accept_review') THEN 'accepted'
 ELSE 'submitted' END AS state
 FROM atlas.teaching_course_private_answer_submissions s
 JOIN atlas.teaching_course_private_study_answer_revisions a ON a.answer_revision_id=s.answer_revision_id
 JOIN atlas.teaching_course_private_study_invitations i ON i.invitation_id=a.invitation_id
 JOIN LATERAL (SELECT d.decision,d.snapshot_id FROM atlas.teaching_course_private_study_unit_decisions d
 WHERE d.invitation_id=i.invitation_id AND d.unit_id=a.unit_id ORDER BY event_seq DESC LIMIT 1) d ON d.decision='allow' AND d.snapshot_id=a.snapshot_id
 WHERE s.reviewer_person_entity_id=v_person AND i.course_id=v_course AND i.invited_by_person_entity_id=v_person
 AND atlas.private_course_study_current_v1(v_course,i.learner_person_entity_id)
 AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='withdraw')
 AND (p_before IS NULL OR (s.recorded_at,s.submission_id)<(v_before_at,p_before))
 ORDER BY s.recorded_at DESC,s.submission_id DESC LIMIT 21
 ) q;
 RETURN jsonb_build_object('contractVersion','private_answer_review_inbox_v1','courseId',v_course,
 'items',CASE WHEN jsonb_array_length(items)>20 THEN items-20 ELSE items END,
 'more',jsonb_array_length(items)>20);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(uuid),
 public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(uuid),
 public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid) TO authenticated;

-- T5e: exact issued Question context and deliberately submitted revision
-- history. Existing current-edition and withdrawal boundaries remain intact.
CREATE FUNCTION atlas.private_answer_question_history_v1(
 a atlas.teaching_course_private_study_answer_revisions,p_reviewer uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE items jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object('submissionId',q.submission_id,
  'answerRevisionId',q.answer_revision_id,'revisionNumber',q.revision_no,
  'recordedAt',q.recorded_at,'state',q.state) ORDER BY q.revision_no DESC),'[]'::jsonb)
 INTO items FROM (
 SELECT s.submission_id,s.answer_revision_id,s.recorded_at,r.revision_no,
 CASE WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='withdraw') THEN 'withdrawn'
 WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='feedback') THEN 'feedback'
 WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='accept_review') THEN 'accepted'
 ELSE 'submitted' END AS state
 FROM atlas.teaching_course_private_answer_submissions s
 JOIN atlas.teaching_course_private_study_answer_revisions r ON r.answer_revision_id=s.answer_revision_id
 WHERE r.invitation_id=a.invitation_id AND r.unit_id=a.unit_id AND r.snapshot_id=a.snapshot_id
 AND r.unit_revision_id=a.unit_revision_id AND r.activity_id=a.activity_id
 AND r.learner_person_entity_id=a.learner_person_entity_id AND s.learner_person_entity_id=a.learner_person_entity_id
 AND s.reviewer_person_entity_id=p_reviewer
 AND (p_mode='learner' OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='withdraw'))
 ORDER BY r.revision_no DESC LIMIT 101
 ) q;
 IF jsonb_array_length(items)>100 THEN RAISE EXCEPTION 'submitted history exceeds bounded view' USING ERRCODE='54000'; END IF;
 RETURN items;
END $$;
REVOKE ALL ON FUNCTION atlas.private_answer_question_history_v1(atlas.teaching_course_private_study_answer_revisions,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_answer_question_context_self_api_v1(p_submission_id uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE j jsonb;s atlas.teaching_course_private_answer_submissions%ROWTYPE;
 a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;u jsonb;v_text text;
 lines text[];i integer;v_prompt text:=NULL;v_marker text;
BEGIN
 j:=public.shared_teaching_private_answer_submission_read_self_api_v1(p_submission_id,p_mode);
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE submission_id=p_submission_id;
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=s.answer_revision_id;
 -- The existing read above authorizes this exact submission and locks its
 -- scope. Before acceptance do not disclose even the original prompt.
 IF p_mode='learner' OR j->>'state' IN ('accepted','feedback') THEN
  SELECT q.item INTO u FROM atlas.teaching_course_version_curriculum_snapshots snap
  CROSS JOIN LATERAL jsonb_array_elements(snap.curriculum_payload->'units') q(item)
  WHERE snap.snapshot_id=a.snapshot_id AND q.item->>'unitId'=a.unit_id::text
  AND q.item->>'revisionId'=a.unit_revision_id::text;
  v_text:=u->>'text';
  IF NOT atlas.private_study_question_valid_v1(v_text,a.activity_id) THEN
   RAISE EXCEPTION 'exact issued question unavailable' USING ERRCODE='42501'; END IF;
  v_marker:='## question {#titus-activity:'||a.activity_id::text||'}';
  lines:=string_to_array(replace(replace(v_text,E'\r\n',E'\n'),E'\r',E'\n'),E'\n');
  FOR i IN 1..coalesce(array_length(lines,1),0) LOOP
   IF lower(lines[i])=v_marker THEN
    i:=i+1;
    WHILE i<=array_length(lines,1) AND btrim(lines[i])='' LOOP i:=i+1; END LOOP;
    WHILE i<=array_length(lines,1) AND btrim(lines[i])<>'' AND lines[i] !~ '^\s*(#|>|[-*] |\d+\. |\||:::|\x60{3,}|~{3,})' LOOP
     v_prompt:=concat_ws(E'\n',v_prompt,lines[i]);i:=i+1;
    END LOOP;
    EXIT;
   END IF;
  END LOOP;
  IF v_prompt IS NULL OR btrim(v_prompt)='' THEN RAISE EXCEPTION 'exact prompt unavailable' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN jsonb_build_object('contractVersion','private_answer_question_context_v1',
  'submissionId',p_submission_id,'snapshotId',a.snapshot_id,'unitRevisionId',a.unit_revision_id,'activityId',a.activity_id,
  'state',j->'state','unitTitle',CASE WHEN v_prompt IS NULL THEN NULL ELSE u->>'title' END,'prompt',v_prompt,
  'history',atlas.private_answer_question_history_v1(a,s.reviewer_person_entity_id,p_mode),'notebookDisclosed',false);
END $$;

-- Learner can find deliberately submitted earlier revisions from their own
-- currently saved answer even when that current answer was never submitted.
CREATE FUNCTION public.shared_teaching_private_answer_own_history_self_api_v1(p_answer_revision_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;v_person uuid;reviewer uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions
 WHERE answer_revision_id=p_answer_revision_id AND learner_person_entity_id=v_person;
 IF a.answer_revision_id IS NULL THEN RAISE EXCEPTION 'own saved answer required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 SELECT invited_by_person_entity_id INTO reviewer FROM atlas.teaching_course_private_study_invitations WHERE invitation_id=a.invitation_id;
 RETURN jsonb_build_object('contractVersion','private_answer_own_history_v1','answerRevisionId',p_answer_revision_id,
  'history',atlas.private_answer_question_history_v1(a,reviewer,'learner'),'notebookDisclosed',false);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_answer_question_context_self_api_v1(uuid,text),
 public.shared_teaching_private_answer_own_history_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_answer_question_context_self_api_v1(uuid,text),
 public.shared_teaching_private_answer_own_history_self_api_v1(uuid) TO authenticated;

-- Transactional shape and ACL assertions; no user records read.
DO $post$
DECLARE name text;rel regclass;proc regprocedure;role_name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['atlas.teaching_course_composition_revisions',
 'atlas.teaching_course_version_curriculum_snapshots',
 'atlas.teaching_course_private_study_invitations',
 'atlas.teaching_course_private_study_responses',
 'atlas.teaching_course_private_study_terminations',
 'atlas.teaching_course_private_study_unit_decisions',
 'atlas.teaching_course_private_study_answer_revisions',
 'atlas.teaching_course_private_answer_submissions',
 'atlas.teaching_course_private_answer_review_events']
 LOOP
  rel:=to_regclass(name);
  IF rel IS NULL OR NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=rel AND c.relrowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=rel AND NOT t.tgisinternal AND t.tgenabled='O' AND (t.tgtype::integer & 16)=16 AND (t.tgtype::integer & 8)=8)
  THEN RAISE EXCEPTION 'private immutable source shape missing: %',name;END IF;
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
   THEN RAISE EXCEPTION 'direct private table grant: %',name;END IF;
  END LOOP;
 END LOOP;
 FOREACH name IN ARRAY ARRAY['public.shared_teaching_course_composition_read_self_api_v1(uuid)',
 'public.shared_teaching_course_composition_save_self_api_v1(uuid,uuid,integer,jsonb)',
 'public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])',
 'public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid)',
 'public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)',
 'public.shared_teaching_private_study_invite_self_api_v1(uuid,uuid,uuid,timestamptz)',
 'public.shared_teaching_private_study_offer_read_self_api_v1(uuid)',
 'public.shared_teaching_private_study_respond_self_api_v1(uuid,uuid,text)',
 'public.shared_teaching_private_study_withdraw_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_study_unit_decide_self_api_v1(uuid,uuid,uuid,text,uuid)',
 'public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_study_index_self_api_v1(uuid)',
 'public.shared_teaching_private_study_delivery_self_api_v1(uuid)',
 'public.shared_teaching_private_study_prepare_edition_self_api_v1(uuid,uuid,text)',
 'public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid)',
 'public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)',
 'public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid)',
 'public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text)',
 'public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text)',
 'public.shared_teaching_private_answer_review_target_self_api_v1(uuid)',
 'public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid)',
 'public.shared_teaching_private_answer_question_context_self_api_v1(uuid,text)',
 'public.shared_teaching_private_answer_own_history_self_api_v1(uuid)']
 LOOP
  proc:=to_regprocedure(name);
  IF proc IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=proc AND p.prosecdef
    AND p.proconfig @> ARRAY['search_path=pg_catalog'])
   OR NOT has_function_privilege('authenticated',proc,'EXECUTE')
   OR has_function_privilege('anon',proc,'EXECUTE')
  THEN RAISE EXCEPTION 'signed source surface shape failed: %',name;END IF;
 END LOOP;
END $post$;

COMMIT;
