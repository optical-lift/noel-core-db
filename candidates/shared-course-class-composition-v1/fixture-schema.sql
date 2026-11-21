-- Disposable schema approximation: NOT the real signed identity implementation.
CREATE SCHEMA atlas;CREATE SCHEMA reality;CREATE SCHEMA auth;
CREATE ROLE anon NOLOGIN;CREATE ROLE authenticated NOLOGIN;CREATE ROLE service_role NOLOGIN;
CREATE TABLE reality.entities(id uuid PRIMARY KEY);
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('fixture.subject',true),'')::uuid $$;
CREATE TABLE atlas.teaching_courses(id uuid PRIMARY KEY,created_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),status text NOT NULL);
CREATE TABLE atlas.teaching_course_units(unit_id uuid PRIMARY KEY,course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id),kind text NOT NULL,title text NOT NULL,display_position integer NOT NULL);
CREATE FUNCTION atlas.current_person_for_private_course_v1() RETURNS uuid LANGUAGE sql STABLE SET search_path TO pg_catalog AS $$ SELECT auth.uid() $$;
CREATE FUNCTION atlas.require_private_course_author_self_v1(p_course_id uuid,p_write boolean) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_course uuid;
BEGIN
 IF p_write AND current_setting('fixture.access',true) IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'grant' USING ERRCODE='42501';END IF;
 IF p_write THEN SELECT id INTO v_course FROM atlas.teaching_courses WHERE id=p_course_id AND created_by_person_entity_id=auth.uid() AND status='active' FOR UPDATE;
 ELSE SELECT id INTO v_course FROM atlas.teaching_courses WHERE id=p_course_id AND created_by_person_entity_id=auth.uid();END IF;
 IF v_course IS NULL THEN RAISE EXCEPTION 'owner' USING ERRCODE='42501';END IF;RETURN v_course;
END $$;
INSERT INTO reality.entities VALUES ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
INSERT INTO auth.users SELECT id FROM reality.entities;
INSERT INTO atlas.teaching_courses VALUES ('00000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000001','active'),('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000002','active');
INSERT INTO atlas.teaching_course_units VALUES
 ('00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000010','lesson','Original root',1024),
 ('00000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-000000000010','assignment','Ordinary work',2048),
 ('00000000-0000-4000-8000-000000000013','00000000-0000-4000-8000-000000000010','lesson','Additional reading',3072),
 ('00000000-0000-4000-8000-000000000014','00000000-0000-4000-8000-000000000010','assignment','Further research',4096),
 ('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000020','lesson','Other root',1024);
