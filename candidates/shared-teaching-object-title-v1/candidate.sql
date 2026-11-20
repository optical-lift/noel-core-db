-- HELD SOURCE CANDIDATE. Disposable schema clone only; no migration admission.
-- Same original Course and Unit, original founder and authored text unchanged.
-- Dependencies: released 20261118190508 and 20261119165500.
BEGIN;
CREATE TABLE atlas.teaching_object_title_revisions (
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 object_kind text NOT NULL CHECK(object_kind IN ('course','unit')),
 object_id uuid NOT NULL,
 unit_id uuid REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 revision_number integer NOT NULL CHECK(revision_number>0),
 previous_title text NOT NULL,
 title text NOT NULL CHECK(title=btrim(title) AND char_length(title) BETWEEN 1 AND 150),
 recorded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((object_kind='course' AND object_id=course_id AND unit_id IS NULL)
       OR (object_kind='unit' AND unit_id IS NOT NULL AND unit_id=object_id)),
 CHECK(previous_title<>title),
 UNIQUE(course_id,request_id),
 UNIQUE(course_id,object_kind,object_id,revision_number)
);
ALTER TABLE atlas.teaching_object_title_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_object_title_revisions FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION atlas.reject_teaching_object_title_revision_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog
AS $$ BEGIN RAISE EXCEPTION 'title revision originals are immutable' USING ERRCODE='55000'; END $$;
REVOKE ALL ON FUNCTION atlas.reject_teaching_object_title_revision_mutation_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER teaching_object_title_revision_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.teaching_object_title_revisions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_teaching_object_title_revision_mutation_v1();

CREATE FUNCTION public.shared_teaching_object_title_read_self_api_v1(p_course_id uuid,p_unit_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $title_read$
DECLARE v_course uuid;v_kind text;v_object uuid;v_title text;v_revision integer;v_last atlas.teaching_object_title_revisions%ROWTYPE;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 v_kind:=CASE WHEN p_unit_id IS NULL THEN 'course' ELSE 'unit' END;
 v_object:=coalesce(p_unit_id,v_course);
 IF p_unit_id IS NULL THEN
  SELECT name INTO v_title FROM atlas.teaching_courses WHERE id=v_course;
 ELSE
  SELECT title INTO v_title FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit_id;
 END IF;
 IF v_title IS NULL THEN RAISE EXCEPTION 'authorized object required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_last FROM atlas.teaching_object_title_revisions
  WHERE course_id=v_course AND object_kind=v_kind AND object_id=v_object ORDER BY revision_number DESC LIMIT 1;
 IF v_last.revision_id IS NOT NULL AND v_last.title IS DISTINCT FROM v_title THEN
  RAISE EXCEPTION 'title source diverged' USING ERRCODE='55000';
 END IF;
 v_revision:=coalesce(v_last.revision_number,0);
 RETURN jsonb_build_object('contractVersion','shared_teaching_object_title_v1',
  'courseId',v_course,'unitId',p_unit_id,'title',v_title,'revisionNumber',v_revision,
  'revisionId',v_last.revision_id,'requestId',v_last.request_id);
END
$title_read$;

CREATE FUNCTION public.shared_teaching_object_title_save_self_api_v1(
 p_course_id uuid,p_unit_id uuid,p_request_id uuid,p_expected_revision integer,
 p_expected_title text,p_title text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $title_save$
DECLARE v_course uuid;v_person uuid;v_kind text;v_object uuid;v_title text;v_current jsonb;
 v_prior atlas.teaching_object_title_revisions%ROWTYPE;v_receipt atlas.teaching_object_title_revisions%ROWTYPE;
BEGIN
 IF p_request_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
  OR p_expected_revision>=100000 OR p_expected_title IS NULL OR p_title IS NULL
  OR p_title<>btrim(p_title) OR char_length(p_title) NOT BETWEEN 1 AND 150
  OR p_title ~ '[[:cntrl:]]' OR p_expected_title=p_title THEN
  RAISE EXCEPTION 'invalid title request' USING ERRCODE='22023';
 END IF;
 -- Existing guarded Course row lock serializes mutations; no new authority.
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 v_kind:=CASE WHEN p_unit_id IS NULL THEN 'course' ELSE 'unit' END;
 v_object:=coalesce(p_unit_id,v_course);
 v_current:=public.shared_teaching_object_title_read_self_api_v1(v_course,p_unit_id);
 SELECT * INTO v_prior FROM atlas.teaching_object_title_revisions WHERE course_id=v_course AND request_id=p_request_id;
 IF v_prior.revision_id IS NOT NULL THEN
  IF v_prior.object_kind<>v_kind OR v_prior.object_id<>v_object
   OR v_prior.revision_number<>p_expected_revision+1
   OR v_prior.previous_title IS DISTINCT FROM p_expected_title OR v_prior.title IS DISTINCT FROM p_title THEN
   RAISE EXCEPTION 'replayed title request differs' USING ERRCODE='23505';
  END IF;
  v_receipt:=v_prior;
 ELSE
  v_title:=v_current->>'title';
  IF (v_current->>'revisionNumber')::integer<>p_expected_revision OR v_title IS DISTINCT FROM p_expected_title THEN
   RAISE EXCEPTION 'stale title revision' USING ERRCODE='40001';
  END IF;
  INSERT INTO atlas.teaching_object_title_revisions(course_id,object_kind,object_id,unit_id,request_id,
     revision_number,previous_title,title,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(v_course,v_kind,v_object,p_unit_id,p_request_id,p_expected_revision+1,
     v_title,p_title,v_person,auth.uid()) RETURNING * INTO v_receipt;
  IF p_unit_id IS NULL THEN
   UPDATE atlas.teaching_courses SET name=p_title WHERE id=v_course;
  ELSE
   UPDATE atlas.teaching_course_units SET title=p_title WHERE course_id=v_course AND unit_id=p_unit_id;
  END IF;
 END IF;
 RETURN jsonb_build_object('contractVersion','shared_teaching_object_title_saved_v1',
  'courseId',v_course,'unitId',p_unit_id,'requestId',v_receipt.request_id,
  'revisionId',v_receipt.revision_id,'revisionNumber',v_receipt.revision_number,'title',v_receipt.title,
  'current',public.shared_teaching_object_title_read_self_api_v1(v_course,p_unit_id));
END
$title_save$;
REVOKE ALL ON FUNCTION public.shared_teaching_object_title_read_self_api_v1(uuid,uuid),
 public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_object_title_read_self_api_v1(uuid,uuid),
 public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text) TO authenticated;

-- Keep create replay semantics tied to the original founding label, not its
-- mutable current title. Exact existing functions otherwise unchanged.
CREATE OR REPLACE FUNCTION public.shared_teaching_course_create_self_api_v1(
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
 WHERE created_by_person_entity_id=v_person AND create_request_id=p_request_id FOR UPDATE;
 IF v_found.id IS NOT NULL THEN
  IF coalesce((SELECT r.previous_title FROM atlas.teaching_object_title_revisions r
    WHERE r.course_id=v_found.id AND r.object_kind='course'
      AND r.object_id=v_found.id AND r.revision_number=1),v_found.name)
    IS DISTINCT FROM v_title THEN
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
CREATE OR REPLACE FUNCTION public.shared_teaching_course_unit_create_self_api_v1(
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
     OR coalesce((SELECT r.previous_title FROM atlas.teaching_object_title_revisions r
     WHERE r.course_id=v_course AND r.object_kind='unit'
       AND r.object_id=v_previous.unit_id AND r.revision_number=1),v_previous.title)
       IS DISTINCT FROM v_title THEN
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
COMMIT;
