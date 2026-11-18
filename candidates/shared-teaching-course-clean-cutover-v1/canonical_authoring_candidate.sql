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
 FROM PUBLIC,anon,authenticated;

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
FROM PUBLIC,anon,authenticated;
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
