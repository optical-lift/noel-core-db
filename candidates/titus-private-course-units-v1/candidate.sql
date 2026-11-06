-- Titus reusable private Course Studio: ordered lessons/homework, each with
-- independently saved append-only material. SOURCE CANDIDATE; NOT A MIGRATION.
-- No real SK 101 content, no default classes, no students/Offerings/publishing.
-- Depends on already released customer Course and original manuscript sources.
BEGIN;

CREATE TABLE titus.customer_course_units_v1(
 unit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES titus.customer_course_drafts_v1(course_id) ON DELETE RESTRICT,
 create_request_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('lesson','assignment')),
 title text NOT NULL CHECK(title=btrim(title) AND length(title) BETWEEN 1 AND 150),
 display_position integer NOT NULL CHECK(display_position>0),
 created_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT titus_unit_request_per_course_v1 UNIQUE(course_id,create_request_id)
);
CREATE INDEX titus_unit_outline_by_course_v1 ON
 titus.customer_course_units_v1(course_id,display_position,unit_id);

CREATE TABLE titus.customer_course_unit_revisions_v1(
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 unit_id uuid NOT NULL REFERENCES titus.customer_course_units_v1(unit_id) ON DELETE RESTRICT,
 edit_request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK(based_on_revision>=0),
 revision_number integer NOT NULL CHECK(revision_number=based_on_revision+1 AND revision_number>0),
 body_text text NOT NULL CHECK(char_length(body_text)<=20000),
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT titus_unit_edit_request_unique_v1 UNIQUE(unit_id,edit_request_id),
 CONSTRAINT titus_unit_revision_unique_v1 UNIQUE(unit_id,revision_number)
);
CREATE INDEX titus_unit_latest_revision_v1 ON
 titus.customer_course_unit_revisions_v1(unit_id,revision_number DESC);
ALTER TABLE titus.customer_course_units_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.customer_course_unit_revisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.customer_course_units_v1,titus.customer_course_unit_revisions_v1 FROM PUBLIC,authenticated,anon,service_role;

-- This is an internal helper, not a browser-facing function. It reuses the
-- released current *live* GoTrue session + independently issued entitlement.
-- A known Course UUID never grants rights. Suspended owners are denied.
CREATE FUNCTION titus.customer_owned_course_for_units_v1(p_course_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog AS $owned$
DECLARE v_user uuid;v_found uuid;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_course_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 SELECT c.course_id INTO v_found
 FROM titus.customer_course_drafts_v1 c
 JOIN titus.customer_workspaces_v1 w ON w.workspace_id=c.workspace_id
 WHERE c.course_id=p_course_id AND c.state='draft'
   AND w.owner_auth_user_id=v_user AND w.state='active';
 IF v_found IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 RETURN v_found;
END $owned$;
REVOKE ALL ON FUNCTION titus.customer_owned_course_for_units_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- One owner-visible ordered outline. No automatic Course or content creation.
CREATE FUNCTION public.titus_customer_outline_read_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $outline$
DECLARE v_course uuid;v_units jsonb;
BEGIN
 v_course:=titus.customer_owned_course_for_units_v1(p_course_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'unitId',u.unit_id,'kind',u.kind,'title',u.title,
   'position',u.display_position,'createdAt',u.created_at)
  ORDER BY u.display_position,u.unit_id),'[]'::jsonb) INTO v_units
 FROM titus.customer_course_units_v1 u WHERE u.course_id=v_course;
 RETURN jsonb_build_object('contractVersion','titus_customer_outline_v1',
   'courseId',v_course,'units',v_units);
END $outline$;

-- A real owner chooses type and title. No course templates or Song data seeding.
CREATE FUNCTION public.titus_customer_unit_create_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_kind text,p_title text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $create$
DECLARE v_user uuid;v_course uuid;v_previous titus.customer_course_units_v1%ROWTYPE;
 v_position integer;v_count integer;v_title text:=btrim(coalesce(p_title,''));
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_request_id IS NULL OR p_kind NOT IN ('lesson','assignment')
   OR length(v_title) NOT BETWEEN 1 AND 150 THEN
  RAISE EXCEPTION 'Valid unit type, title, and request ID required' USING ERRCODE='22023';
 END IF;
 -- Serialize this buyer's creates/reordering/saves without locking other buyers.
 PERFORM 1 FROM titus.customer_workspaces_v1 w
 WHERE w.owner_auth_user_id=v_user AND w.state='active' FOR UPDATE;
 v_course:=titus.customer_owned_course_for_units_v1(p_course_id);
 SELECT * INTO v_previous FROM titus.customer_course_units_v1 u
 WHERE u.course_id=v_course AND u.create_request_id=p_request_id;
 IF v_previous.unit_id IS NOT NULL THEN
  IF v_previous.kind IS DISTINCT FROM p_kind OR v_previous.title IS DISTINCT FROM v_title THEN
   RAISE EXCEPTION 'Original unit request conflicts' USING ERRCODE='23505';
  END IF;
  RETURN public.titus_customer_outline_read_self_api_v1(v_course);
 END IF;
 SELECT count(*),coalesce(max(display_position),0)+1024 INTO v_count,v_position
 FROM titus.customer_course_units_v1 WHERE course_id=v_course;
 IF v_count>=100 THEN
  RAISE EXCEPTION 'Course unit limit reached' USING ERRCODE='22023';
 END IF;
 INSERT INTO titus.customer_course_units_v1(
  course_id,create_request_id,kind,title,display_position,created_by_auth_user_id)
 VALUES(v_course,p_request_id,p_kind,v_title,v_position,v_user);
 RETURN public.titus_customer_outline_read_self_api_v1(v_course);
END $create$;

-- Bounded one-place up/down motion, never a caller-written global position.
-- No new units or body changes. Same workspace lock as create/write.
CREATE FUNCTION public.titus_customer_unit_move_self_api_v1(
 p_course_id uuid,p_unit_id uuid,p_direction text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $move$
DECLARE v_user uuid;v_unit titus.customer_course_units_v1%ROWTYPE;
 v_neighbor titus.customer_course_units_v1%ROWTYPE;v_course uuid;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_course_id IS NULL OR p_unit_id IS NULL OR p_direction NOT IN ('up','down') THEN
  RAISE EXCEPTION 'Invalid unit move' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM titus.customer_workspaces_v1 w
 WHERE w.owner_auth_user_id=v_user AND w.state='active' FOR UPDATE;
 v_course:=titus.customer_owned_course_for_units_v1(p_course_id);
 SELECT * INTO v_unit FROM titus.customer_course_units_v1
 WHERE unit_id=p_unit_id AND course_id=v_course;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 IF p_direction='up' THEN
  SELECT * INTO v_neighbor FROM titus.customer_course_units_v1
  WHERE course_id=v_course AND display_position<v_unit.display_position
  ORDER BY display_position DESC,unit_id DESC LIMIT 1;
 ELSE
  SELECT * INTO v_neighbor FROM titus.customer_course_units_v1
  WHERE course_id=v_course AND display_position>v_unit.display_position
  ORDER BY display_position ASC,unit_id ASC LIMIT 1;
 END IF;
 IF v_neighbor.unit_id IS NOT NULL THEN
  UPDATE titus.customer_course_units_v1 SET
   display_position=CASE WHEN unit_id=v_unit.unit_id THEN v_neighbor.display_position
                     WHEN unit_id=v_neighbor.unit_id THEN v_unit.display_position
                     ELSE display_position END
  WHERE unit_id IN (v_unit.unit_id,v_neighbor.unit_id);
 END IF;
 RETURN public.titus_customer_outline_read_self_api_v1(v_course);
END $move$;

-- Each class/homework owns a distinct append-only writing history.
CREATE FUNCTION public.titus_customer_unit_read_self_api_v1(p_unit_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $read$
DECLARE v_unit titus.customer_course_units_v1%ROWTYPE;
 v_revision titus.customer_course_unit_revisions_v1%ROWTYPE;v_course uuid;
BEGIN
 PERFORM titus.customer_current_auth_user_v1();
 IF p_unit_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_unit FROM titus.customer_course_units_v1 WHERE unit_id=p_unit_id;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 v_course:=titus.customer_owned_course_for_units_v1(v_unit.course_id);
 SELECT * INTO v_revision FROM titus.customer_course_unit_revisions_v1
 WHERE unit_id=v_unit.unit_id ORDER BY revision_number DESC LIMIT 1;
 RETURN jsonb_build_object('contractVersion','titus_customer_unit_material_v1',
  'courseId',v_course,'unit',jsonb_build_object(
    'unitId',v_unit.unit_id,'kind',v_unit.kind,'title',v_unit.title),
  'material',CASE WHEN v_revision.revision_id IS NULL THEN NULL ELSE jsonb_build_object(
    'revisionId',v_revision.revision_id,'revisionNumber',v_revision.revision_number,
    'text',v_revision.body_text,'savedAt',v_revision.recorded_at) END);
END $read$;

CREATE FUNCTION public.titus_customer_unit_save_self_api_v1(
 p_unit_id uuid,p_request_id uuid,p_expected_revision integer,p_text text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $save$
DECLARE v_user uuid;v_unit titus.customer_course_units_v1%ROWTYPE;
 v_previous titus.customer_course_unit_revisions_v1%ROWTYPE;
 v_course uuid;v_latest integer;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_unit_id IS NULL OR p_request_id IS NULL OR p_text IS NULL OR
   p_expected_revision IS NULL OR p_expected_revision<0 OR
   p_expected_revision>=10000 OR char_length(p_text)>20000 THEN
  RAISE EXCEPTION 'Invalid unit material write' USING ERRCODE='22023';
 END IF;
 PERFORM 1 FROM titus.customer_workspaces_v1 w
 WHERE w.owner_auth_user_id=v_user AND w.state='active' FOR UPDATE;
 SELECT * INTO v_unit FROM titus.customer_course_units_v1 WHERE unit_id=p_unit_id;
 IF v_unit.unit_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 v_course:=titus.customer_owned_course_for_units_v1(v_unit.course_id);
 SELECT * INTO v_previous FROM titus.customer_course_unit_revisions_v1
 WHERE unit_id=v_unit.unit_id AND edit_request_id=p_request_id;
 IF v_previous.revision_id IS NOT NULL THEN
  IF v_previous.based_on_revision IS DISTINCT FROM p_expected_revision
    OR v_previous.body_text IS DISTINCT FROM p_text THEN
   RAISE EXCEPTION 'Unit request conflicts with prior original' USING ERRCODE='23505';
  END IF;
  RETURN public.titus_customer_unit_read_self_api_v1(v_unit.unit_id);
 END IF;
 SELECT coalesce(max(revision_number),0) INTO v_latest
 FROM titus.customer_course_unit_revisions_v1 WHERE unit_id=v_unit.unit_id;
 IF v_latest<>p_expected_revision THEN
  RAISE EXCEPTION 'Unit revision is out of date' USING ERRCODE='40001';
 END IF;
 INSERT INTO titus.customer_course_unit_revisions_v1(
  unit_id,edit_request_id,based_on_revision,revision_number,body_text,
  recorded_by_auth_user_id)
 VALUES(v_unit.unit_id,p_request_id,v_latest,v_latest+1,p_text,v_user);
 RETURN public.titus_customer_unit_read_self_api_v1(v_unit.unit_id);
END $save$;

-- No implicit PUBLIC, direct anon or service-role EXECUTE. Explicit
-- authenticated grant is not permission without verified session/entitlement.
REVOKE ALL ON FUNCTION
 public.titus_customer_outline_read_self_api_v1(uuid),
 public.titus_customer_unit_create_self_api_v1(uuid,uuid,text,text),
 public.titus_customer_unit_move_self_api_v1(uuid,uuid,text),
 public.titus_customer_unit_read_self_api_v1(uuid),
 public.titus_customer_unit_save_self_api_v1(uuid,uuid,integer,text)
 FROM PUBLIC,anon,service_role,authenticated;
GRANT EXECUTE ON FUNCTION
 public.titus_customer_outline_read_self_api_v1(uuid),
 public.titus_customer_unit_create_self_api_v1(uuid,uuid,text,text),
 public.titus_customer_unit_move_self_api_v1(uuid,uuid,text),
 public.titus_customer_unit_read_self_api_v1(uuid),
 public.titus_customer_unit_save_self_api_v1(uuid,uuid,integer,text)
 TO authenticated;
COMMIT;
