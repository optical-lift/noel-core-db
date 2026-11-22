-- HELD SOURCE CANDIDATE. Protected clone only until exact owner release.
-- SK101 coordinated management facade. No real Course data or grant is touched.
BEGIN;

ALTER TABLE atlas.teaching_course_unit_revisions ADD COLUMN IF NOT EXISTS recovered_from_revision_id uuid REFERENCES atlas.teaching_course_unit_revisions(revision_id) ON DELETE RESTRICT;
CREATE TABLE IF NOT EXISTS atlas.teaching_course_unit_order_revisions (revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,edit_request_id uuid NOT NULL,based_on_revision integer NOT NULL CHECK (based_on_revision BETWEEN 0 AND 99999),revision_number integer NOT NULL CHECK (revision_number=based_on_revision+1),moved_unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,position integer NOT NULL CHECK (position>0),ordering jsonb NOT NULL CHECK (jsonb_typeof(ordering)='array'),recorded_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id),recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id),recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(course_id,edit_request_id),UNIQUE(course_id,revision_number));
ALTER TABLE atlas.teaching_course_unit_order_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.teaching_course_unit_order_revisions FROM PUBLIC,anon,authenticated,service_role;
-- Separate command admission. This does not alter existing save_draft authority.
INSERT INTO atlas.agent_command_definitions
(command_key,command_version,label,scope_kind,execution_class,confirmation_requirement,handler_key,status,input_contract,target_contract)
VALUES
('teaching.course.management.read',1,'Read private Course management state','personal','read','none',
 'teaching.course.management.read.v1','active',
 '{"contractVersion":"atlas_course_management_request_v1","operation":"fixed_allowlist"}'::jsonb,
 '{"kind":"teaching_course"}'::jsonb),
('teaching.course.management.write',1,'Write private Course management state','personal','commit','none',
 'teaching.course.management.write.v1','active',
 '{"contractVersion":"atlas_course_management_request_v1","operation":"fixed_allowlist","requestId":"uuid"}'::jsonb,
 '{"kind":"teaching_course"}'::jsonb)
ON CONFLICT (command_key,command_version) DO NOTHING;

CREATE OR REPLACE FUNCTION atlas.require_private_course_management_v1(
 p_token_hash text,p_course uuid,p_command text,p_write boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE v_auth uuid; v_course uuid;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
  OR p_course IS NULL OR p_command NOT IN
   ('teaching.course.management.read','teaching.course.management.write')
 THEN RAISE EXCEPTION 'exact Course management grant required' USING ERRCODE='42501'; END IF;
 SELECT authorization_id INTO v_auth FROM atlas.delegated_agent_credentials
 WHERE token_hash=lower(p_token_hash) AND credential_state='active'
   AND begins_at<=clock_timestamp() AND (expires_at IS NULL OR expires_at>clock_timestamp());
 IF v_auth IS NULL
 THEN RAISE EXCEPTION 'exact Course management grant required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations a
   WHERE a.id=v_auth AND a.authorization_state='active'
   AND a.allowed_command_keys @> ARRAY[p_command]::text[]
   AND NOT (p_command=ANY(a.denied_command_keys))
   AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),
                                  'targetIds',jsonb_build_array(p_course::text)))
 THEN RAISE EXCEPTION 'exact Course management command admission required' USING ERRCODE='42501'; END IF;
 SELECT id INTO v_course FROM atlas.teaching_courses
 WHERE id=p_course AND status='active' AND ledger_id IS NULL;
 IF v_course IS NULL THEN RAISE EXCEPTION 'original Course required' USING ERRCODE='42501'; END IF;
 RETURN v_course;
END $$;

CREATE OR REPLACE FUNCTION public.shared_delegated_course_management_read_service_v1(
 p_token_hash text,p_course uuid,p_operation text,p_unit uuid DEFAULT NULL,
 p_revision uuid DEFAULT NULL,p_reference text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE v_course uuid; v_title text; v_last jsonb; v_units jsonb; v_base jsonb; v_compare jsonb; v_reference uuid;
BEGIN
 v_course:=atlas.require_private_course_management_v1(p_token_hash,p_course,
  'teaching.course.management.read',false);
 IF p_operation IN ('course_title_read','unit_title_read') THEN
  IF p_operation='course_title_read' THEN
   SELECT name INTO v_title FROM atlas.teaching_courses WHERE id=v_course;
  ELSE
   SELECT title INTO v_title FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit;
   IF v_title IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
  END IF;
  SELECT jsonb_build_object('revisionNumber',revision_number,'revisionId',revision_id,
    'requestId',request_id,'title',title) INTO v_last
  FROM atlas.teaching_object_title_revisions
  WHERE course_id=v_course AND object_kind=CASE WHEN p_operation='course_title_read' THEN 'course' ELSE 'unit' END
    AND object_id=CASE WHEN p_operation='course_title_read' THEN v_course ELSE p_unit END
  ORDER BY revision_number DESC LIMIT 1;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_title_read_v1',
   'courseId',v_course,'unitId',p_unit,'title',v_title,
   'revisionNumber',coalesce((v_last->>'revisionNumber')::int,0),
   'revision',v_last);
 END IF;
 IF p_operation='unit_outline_read' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('unitId',unit_id,'kind',kind,
   'title',title,'position',display_position,'createdAt',created_at)
   ORDER BY display_position,unit_id),'[]'::jsonb) INTO v_units
  FROM atlas.teaching_course_units WHERE course_id=v_course;
  SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'requestId',edit_request_id,'ordering',ordering) INTO v_last
   FROM atlas.teaching_course_unit_order_revisions WHERE course_id=v_course ORDER BY revision_number DESC LIMIT 1;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_outline_v1','courseId',v_course,'revisionId',v_last->'revisionId','revisionNumber',coalesce((v_last->>'revisionNumber')::int,0),'requestId',v_last->'requestId','units',v_units);
 END IF;
 IF p_operation='course_material_read' THEN
  SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,
    'text',body_text,'savedAt',recorded_at) INTO v_last
  FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course
  ORDER BY revision_number DESC LIMIT 1;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_material_read_v1',
   'courseId',v_course,'material',v_last);
 END IF;
 IF p_operation='composition_read' THEN
  SELECT jsonb_build_object('contractVersion','shared_teaching_course_composition_v1','courseId',v_course,
    'revisionNumber',coalesce(max(revision_number),0),'members',coalesce((array_agg(members ORDER BY revision_number DESC))[1],'[]'::jsonb))
    INTO v_last FROM atlas.teaching_course_composition_revisions WHERE course_id=v_course;
  RETURN v_last;
 END IF;
 IF p_operation='pending_proposals_read' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('invocationId',id,'createdAt',created_at,
    'state',invocation_state,'proposal',input) ORDER BY created_at),'[]'::jsonb) INTO v_units
  FROM atlas.agent_command_invocations
  WHERE command_key='teaching.course.authoring.apply_proposal'
    AND target=jsonb_build_object('kind','teaching_course','id',v_course::text)
    AND invocation_state IN ('needs_confirmation','authorized');
  RETURN jsonb_build_object('contractVersion','atlas_course_management_pending_proposals_v1',
   'courseId',v_course,'proposals',v_units);
 END IF;
 IF p_operation='revision_history_read' THEN
  IF p_unit IS NULL THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) ORDER BY revision_number),'[]'::jsonb) INTO v_units FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course;
  ELSE
   IF NOT EXISTS (SELECT 1 FROM atlas.teaching_course_units WHERE unit_id=p_unit AND course_id=v_course) THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) ORDER BY revision_number),'[]'::jsonb) INTO v_units FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit;
  END IF;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_revision_read_v1','courseId',v_course,'operation',p_operation,'unitId',p_unit,'revisionId',p_revision,'revisions',v_units);
 END IF;
 IF p_operation='revision_compare' THEN
  IF p_revision IS NULL OR p_reference IS NULL OR p_reference !~ '^[0-9a-fA-F-]{36}$' THEN RAISE EXCEPTION 'two historical revisions required' USING ERRCODE='22023'; END IF;
  v_reference:=p_reference::uuid;
  IF p_unit IS NULL THEN
   SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) INTO v_base FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course AND revision_id=p_revision;
   SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) INTO v_compare FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course AND revision_id=v_reference;
  ELSE
   IF NOT EXISTS (SELECT 1 FROM atlas.teaching_course_units WHERE unit_id=p_unit AND course_id=v_course) THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
   SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) INTO v_base FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit AND revision_id=p_revision;
   SELECT jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at) INTO v_compare FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit AND revision_id=v_reference;
  END IF;
  IF v_base IS NULL OR v_compare IS NULL THEN RAISE EXCEPTION 'historical revision not found' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_revision_compare_v1','courseId',v_course,'unitId',p_unit,'baseRevision',v_base,'compareRevision',v_compare,'same',v_base->>'text'=v_compare->>'text');
 END IF;
 RAISE EXCEPTION 'management read operation not admitted' USING ERRCODE='22023';
END $$;

REVOKE ALL ON FUNCTION public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)
 TO service_role;


CREATE OR REPLACE FUNCTION public.shared_delegated_course_management_write_service_v1(
 p_token_hash text,p_course uuid,p_operation text,p_unit uuid,p_request uuid,
 p_expected_revision integer,p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE v_course uuid; v_auth uuid; v_person uuid; v_user uuid; v_title text; v_old text;
 v_latest integer; v_rev atlas.teaching_object_title_revisions%ROWTYPE; v_prior_manuscript atlas.teaching_course_manuscript_revisions%ROWTYPE;
 v_text text; v_members jsonb; v_expected_title text; v_prior_unit atlas.teaching_course_unit_revisions%ROWTYPE; v_current integer; v_unit atlas.teaching_course_units%ROWTYPE;
 v_prior_order atlas.teaching_course_unit_order_revisions%ROWTYPE; v_ordering jsonb; v_position integer;
 v_source_unit_revision atlas.teaching_course_unit_revisions%ROWTYPE; v_source_revision uuid;
 v_prior_composition atlas.teaching_course_composition_revisions%ROWTYPE;
 v_current_text text; v_base_text text; v_replacement text; v_start integer; v_end integer;
BEGIN
 v_course:=atlas.require_private_course_management_v1(p_token_hash,p_course,
   'teaching.course.management.write',true);
 IF p_request IS NULL OR p_operation NOT IN
  ('course_title_save','unit_title_save','course_material_save','unit_move',
   'composition_save','unit_subsection_save','revision_recover')
 THEN RAISE EXCEPTION 'fixed management write required' USING ERRCODE='22023'; END IF;
 IF p_expected_revision IS NULL OR p_expected_revision<0 OR p_expected_revision>=100000
 THEN RAISE EXCEPTION 'expected revision required' USING ERRCODE='22023'; END IF;
 SELECT c.authorization_id,pr.user_id,b.person_entity_id INTO v_auth,v_user,v_person
 FROM atlas.delegated_agent_credentials c
 JOIN atlas.delegated_agent_authorizations a ON a.id=c.authorization_id
 JOIN atlas.principals pr ON pr.id=a.principal_id
 JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id AND b.binding_state='active' AND b.retired_at IS NULL
 WHERE c.token_hash=lower(p_token_hash) AND c.authorization_id IS NOT NULL LIMIT 1;
 IF v_person IS NULL THEN RAISE EXCEPTION 'canonical Person required' USING ERRCODE='42501'; END IF;
 IF p_operation IN ('unit_title_save','unit_move','unit_subsection_save','revision_recover') THEN
  SELECT * INTO v_unit FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit FOR UPDATE;
  IF v_unit.unit_id IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
 END IF;
 PERFORM 1 FROM atlas.teaching_courses WHERE id=v_course FOR UPDATE;
 IF p_operation IN ('course_title_save','unit_title_save') THEN
  v_title:=p_payload->>'title'; v_expected_title:=p_payload->>'expectedTitle';
  IF v_title IS NULL OR v_title<>btrim(v_title) OR char_length(v_title) NOT BETWEEN 1 AND 150
  THEN RAISE EXCEPTION 'invalid title request' USING ERRCODE='22023'; END IF;
  IF p_operation='course_title_save' THEN
   SELECT name INTO v_old FROM atlas.teaching_courses WHERE id=v_course FOR UPDATE;
  ELSE
   SELECT title INTO v_old FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit FOR UPDATE;
   IF v_old IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
  END IF;
  SELECT * INTO v_rev FROM atlas.teaching_object_title_revisions WHERE course_id=v_course AND request_id=p_request;
  IF v_rev.revision_id IS NOT NULL THEN
   IF v_rev.title IS DISTINCT FROM v_title OR v_rev.previous_title IS DISTINCT FROM coalesce(v_expected_title,v_rev.previous_title)
    OR v_rev.object_id IS DISTINCT FROM (CASE WHEN p_operation='course_title_save' THEN v_course ELSE p_unit END)
   THEN RAISE EXCEPTION 'replayed title request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_rev.revision_id,'revisionNumber',v_rev.revision_number,'title',v_rev.title);
  END IF;
  IF v_old=v_title THEN RAISE EXCEPTION 'title must change' USING ERRCODE='22023'; END IF;
  IF v_expected_title IS NULL OR v_old IS DISTINCT FROM v_expected_title THEN RAISE EXCEPTION 'stale title revision' USING ERRCODE='40001'; END IF;
  IF v_rev.revision_id IS NOT NULL THEN
   IF v_rev.title IS DISTINCT FROM v_title OR v_rev.previous_title IS DISTINCT FROM v_old OR v_rev.object_id IS DISTINCT FROM (CASE WHEN p_operation='course_title_save' THEN v_course ELSE p_unit END)
   THEN RAISE EXCEPTION 'replayed title request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_rev.revision_id,'revisionNumber',v_rev.revision_number,'title',v_rev.title);
  END IF;
  INSERT INTO atlas.teaching_object_title_revisions(course_id,object_kind,object_id,unit_id,request_id,
   revision_number,previous_title,title,recorded_by_person_entity_id,recorded_by_auth_user_id)
  VALUES(v_course,CASE WHEN p_operation='course_title_save' THEN 'course' ELSE 'unit' END,
   CASE WHEN p_operation='course_title_save' THEN v_course ELSE p_unit END,
   CASE WHEN p_operation='course_title_save' THEN NULL ELSE p_unit END,p_request,p_expected_revision+1,
   v_old,v_title,v_person,v_user) RETURNING * INTO v_rev;
  IF p_operation='course_title_save' THEN UPDATE atlas.teaching_courses SET name=v_title WHERE id=v_course;
  ELSE UPDATE atlas.teaching_course_units SET title=v_title WHERE course_id=v_course AND unit_id=p_unit;
  END IF;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1',
   'operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,
   'revisionId',v_rev.revision_id,'revisionNumber',v_rev.revision_number,'title',v_title);
 END IF;
 IF p_operation='unit_subsection_save' THEN
  IF p_payload ? 'text' OR NOT (p_payload ?& ARRAY['baseText','selectionStart','selectionEnd','replacement'])
  THEN RAISE EXCEPTION 'selection witness required' USING ERRCODE='22023'; END IF;
  v_base_text:=p_payload->>'baseText'; v_replacement:=p_payload->>'replacement';
  v_start:=(p_payload->>'selectionStart')::integer; v_end:=(p_payload->>'selectionEnd')::integer;
  IF v_base_text IS NULL OR v_replacement IS NULL OR char_length(v_base_text)>20000 OR char_length(v_replacement)>20000
  THEN RAISE EXCEPTION 'invalid Unit subsection request' USING ERRCODE='22023'; END IF;
  SELECT coalesce(max(revision_number),0) INTO v_latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit;
  SELECT body_text INTO v_current_text FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit ORDER BY revision_number DESC LIMIT 1;
  v_current_text:=coalesce(v_current_text,'');
  IF v_latest<>p_expected_revision THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  IF v_base_text IS DISTINCT FROM v_current_text OR v_start<0 OR v_end<v_start OR v_end>char_length(v_base_text)
  THEN RAISE EXCEPTION 'stale Unit subsection source' USING ERRCODE='40001'; END IF;
  v_text:=left(v_base_text,v_start)||v_replacement||substr(v_base_text,v_end+1);
  IF char_length(v_text)>20000 THEN RAISE EXCEPTION 'invalid Unit revision' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_prior_unit FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit AND edit_request_id=p_request;
  IF v_prior_unit.revision_id IS NOT NULL THEN
   IF v_prior_unit.body_text IS DISTINCT FROM v_text OR v_prior_unit.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_unit.recorded_by_person_entity_id IS DISTINCT FROM v_person OR v_prior_unit.recorded_by_auth_user_id IS DISTINCT FROM v_user
      OR v_prior_unit.recovered_from_revision_id IS NOT NULL
   THEN RAISE EXCEPTION 'replayed Unit request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'textLength',char_length(v_prior_unit.body_text));
  END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(p_unit,p_request,v_latest,v_latest+1,v_text,v_person,v_user) RETURNING * INTO v_prior_unit;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'textLength',char_length(v_text));
 END IF;
 IF p_operation='revision_recover' THEN
  IF p_payload ? 'text' OR NOT (p_payload ? 'revisionId')
  THEN RAISE EXCEPTION 'historical source revision required' USING ERRCODE='22023'; END IF;
  v_source_revision:=(p_payload->>'revisionId')::uuid;
  SELECT r.* INTO v_source_unit_revision FROM atlas.teaching_course_unit_revisions r
   JOIN atlas.teaching_course_units u ON u.unit_id=r.unit_id AND u.course_id=v_course
   WHERE r.unit_id=p_unit AND r.revision_id=v_source_revision;
  IF v_source_unit_revision.revision_id IS NULL THEN RAISE EXCEPTION 'historical source revision not found' USING ERRCODE='42501'; END IF;
  v_text:=v_source_unit_revision.body_text;
  SELECT coalesce(max(revision_number),0) INTO v_latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit;
  IF v_latest<>p_expected_revision THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  SELECT * INTO v_prior_unit FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit AND edit_request_id=p_request;
  IF v_prior_unit.revision_id IS NOT NULL THEN
   IF v_prior_unit.body_text IS DISTINCT FROM v_text OR v_prior_unit.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_unit.recorded_by_person_entity_id IS DISTINCT FROM v_person OR v_prior_unit.recorded_by_auth_user_id IS DISTINCT FROM v_user
      OR v_prior_unit.recovered_from_revision_id IS DISTINCT FROM v_source_revision
   THEN RAISE EXCEPTION 'replayed recovery request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'sourceRevisionId',v_source_revision,'textLength',char_length(v_prior_unit.body_text));
  END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,recovered_from_revision_id,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(p_unit,p_request,v_latest,v_latest+1,v_text,v_source_revision,v_person,v_user) RETURNING * INTO v_prior_unit;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'sourceRevisionId',v_source_revision,'textLength',char_length(v_text));
 END IF;
 IF p_operation='course_material_save' THEN
  v_text:=p_payload->>'text';
  IF v_text IS NULL OR char_length(v_text)>40000 THEN RAISE EXCEPTION 'invalid manuscript request' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_prior_manuscript FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course AND edit_request_id=p_request;
  IF v_prior_manuscript.revision_id IS NOT NULL THEN
   IF v_prior_manuscript.body_text IS DISTINCT FROM v_text
      OR v_prior_manuscript.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_manuscript.recorded_by_person_entity_id IS DISTINCT FROM v_person
      OR v_prior_manuscript.recorded_by_auth_user_id IS DISTINCT FROM v_user
   THEN RAISE EXCEPTION 'replayed manuscript request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'requestId',p_request,'revisionNumber',v_prior_manuscript.revision_number,'textLength',char_length(v_prior_manuscript.body_text));
  END IF;
  SELECT coalesce(max(revision_number),0) INTO v_latest FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course;
  IF v_latest<>p_expected_revision THEN RAISE EXCEPTION 'stale manuscript revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_manuscript_revisions(course_id,edit_request_id,based_on_revision,revision_number,body_text,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(v_course,p_request,v_latest,v_latest+1,v_text,v_person,v_user);
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,
   'courseId',v_course,'requestId',p_request,'revisionNumber',v_latest+1,'textLength',char_length(v_text));
 END IF;
 IF p_operation='composition_save' THEN
  v_members:=p_payload->'members';
  SELECT * INTO v_prior_composition FROM atlas.teaching_course_composition_revisions WHERE course_id=v_course AND edit_request_id=p_request;
  IF v_prior_composition.revision_id IS NOT NULL THEN
   IF v_prior_composition.members IS DISTINCT FROM v_members OR v_prior_composition.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_composition.recorded_by_person_entity_id IS DISTINCT FROM v_person OR v_prior_composition.recorded_by_auth_user_id IS DISTINCT FROM v_user
   THEN RAISE EXCEPTION 'replayed composition request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','shared_teaching_course_composition_v1','operation',p_operation,'courseId',v_course,'requestId',p_request,'revisionNumber',v_prior_composition.revision_number,'members',v_prior_composition.members);
  END IF;
  PERFORM atlas.validate_course_composition_v1(v_course,v_members);
  SELECT coalesce(max(revision_number),0) INTO v_current FROM atlas.teaching_course_composition_revisions WHERE course_id=v_course;
  IF v_current<>p_expected_revision THEN RAISE EXCEPTION 'stale composition revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_composition_revisions(course_id,edit_request_id,based_on_revision,revision_number,members,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(v_course,p_request,v_current,v_current+1,v_members,v_person,v_user) RETURNING * INTO v_prior_composition;
  RETURN jsonb_build_object('contractVersion','shared_teaching_course_composition_v1','operation',p_operation,'courseId',v_course,'requestId',p_request,'revisionNumber',v_prior_composition.revision_number,'members',v_members);
 END IF;
 IF p_operation='unit_move' THEN
  v_position:=(p_payload->>'position')::integer;
  SELECT * INTO v_prior_order FROM atlas.teaching_course_unit_order_revisions WHERE course_id=v_course AND edit_request_id=p_request;
  IF v_prior_order.revision_id IS NOT NULL THEN
   IF v_prior_order.moved_unit_id IS DISTINCT FROM p_unit OR v_prior_order.position IS DISTINCT FROM v_position
      OR v_prior_order.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_order.recorded_by_person_entity_id IS DISTINCT FROM v_person OR v_prior_order.recorded_by_auth_user_id IS DISTINCT FROM v_user
   THEN RAISE EXCEPTION 'replayed ordering request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_order_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_order.revision_id,'revisionNumber',v_prior_order.revision_number,'position',v_prior_order.position,'ordering',v_prior_order.ordering);
  END IF;
  IF v_position IS NULL OR v_position<1 THEN RAISE EXCEPTION 'valid Unit position required' USING ERRCODE='22023'; END IF;
  SELECT coalesce(max(revision_number),0) INTO v_current FROM atlas.teaching_course_unit_order_revisions WHERE course_id=v_course;
  IF v_current<>p_expected_revision THEN RAISE EXCEPTION 'stale ordering revision' USING ERRCODE='40001'; END IF;
  IF v_position>(SELECT count(*) FROM atlas.teaching_course_units WHERE course_id=v_course) THEN RAISE EXCEPTION 'valid Unit position required' USING ERRCODE='22023'; END IF;
  SELECT old_rank INTO v_latest FROM (
   SELECT unit_id,row_number() OVER (ORDER BY display_position,unit_id)::integer AS old_rank
   FROM atlas.teaching_course_units WHERE course_id=v_course
  ) ranked WHERE unit_id=p_unit;
  WITH ranked AS (
   SELECT unit_id,row_number() OVER (ORDER BY display_position,unit_id)::integer AS old_rank
   FROM atlas.teaching_course_units WHERE course_id=v_course
  ), desired AS (
   SELECT unit_id,CASE
    WHEN unit_id=p_unit THEN v_position
    WHEN old_rank<v_latest AND old_rank>=v_position THEN old_rank+1
    WHEN old_rank>v_latest AND old_rank<=v_position THEN old_rank-1
    ELSE old_rank END AS new_position
   FROM ranked
  )
  UPDATE atlas.teaching_course_units u SET display_position=d.new_position
   FROM desired d WHERE d.unit_id=u.unit_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('unitId',unit_id,'position',display_position) ORDER BY display_position,unit_id),'[]'::jsonb) INTO v_ordering FROM atlas.teaching_course_units WHERE course_id=v_course;
  INSERT INTO atlas.teaching_course_unit_order_revisions(course_id,edit_request_id,based_on_revision,revision_number,moved_unit_id,position,ordering,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(v_course,p_request,v_current,v_current+1,p_unit,v_position,v_ordering,v_person,v_user) RETURNING * INTO v_prior_order;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_order_receipt_v1','courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_order.revision_id,'revisionNumber',v_prior_order.revision_number,'position',v_position,'ordering',v_ordering);
 END IF;
 RAISE EXCEPTION 'management write operation not admitted' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)
 TO service_role;

COMMIT;
