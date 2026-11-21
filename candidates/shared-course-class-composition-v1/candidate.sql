-- HELD: private, Person-origin Course working composition, no seeds or release.
BEGIN;
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
COMMIT;
