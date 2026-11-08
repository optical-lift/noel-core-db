-- HELD M3.11 — ONE immutable, privately sealed curriculum snapshot per
-- Person-authored Course Version. This is not institutional disclosure,
-- Course root creation, Offering opening, teacher appointment, or enrollment.
-- The previous M3.9 published Version is definition metadata ONLY. Its
-- historical identity remains unchanged; a distinct author decision copies
-- its own current manuscript + ordered complete Unit revisions at seal time.
-- Applied only on disposable PostgreSQL 17/protected clone, never production.
DO $source_guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
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
   'units',v_units
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
