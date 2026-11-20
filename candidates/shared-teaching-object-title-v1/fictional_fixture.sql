-- Minimal fictional PG17 transaction fixture. NOT a signed-auth proof.
CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA atlas; CREATE SCHEMA reality; CREATE SCHEMA auth; CREATE SCHEMA titus;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE reality.entities(id uuid PRIMARY KEY);
CREATE TABLE atlas.teaching_courses(
 id uuid PRIMARY KEY,course_key text NOT NULL,name text NOT NULL,status text NOT NULL,
 created_by_person_entity_id uuid REFERENCES reality.entities(id),
 created_by_auth_user_id uuid REFERENCES auth.users(id),create_request_id uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(created_by_person_entity_id,create_request_id));
CREATE TABLE titus.fixture_grants(person_id uuid PRIMARY KEY,active boolean NOT NULL);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT current_setting('fixture.actor')::uuid $$;
CREATE FUNCTION atlas.current_person_for_private_course_v1() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT current_setting('fixture.actor')::uuid $$;
CREATE FUNCTION titus.require_authoring_access_v1() RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN IF NOT EXISTS(SELECT 1 FROM titus.fixture_grants WHERE person_id=auth.uid() AND active)
 THEN RAISE EXCEPTION 'fixture grant denied' USING ERRCODE='42501'; END IF;
 RETURN auth.uid(); END $$;
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
INSERT INTO auth.users VALUES ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
INSERT INTO reality.entities SELECT id FROM auth.users;
INSERT INTO titus.fixture_grants SELECT id,true FROM auth.users;
