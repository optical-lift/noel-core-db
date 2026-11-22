-- HELD SOURCE CANDIDATE. Protected clone only until exact owner release.
-- SK101 coordinated management facade. No real Course data or grant is touched.
BEGIN;

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
DECLARE v_course uuid; v_title text; v_last jsonb; v_units jsonb;
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
  RETURN jsonb_build_object('contractVersion','atlas_course_management_outline_v1',
   'courseId',v_course,'units',v_units);
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
 IF p_operation IN ('revision_history_read','revision_compare') THEN
  IF p_unit IS NULL THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,
    'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at)
    ORDER BY revision_number),'[]'::jsonb) INTO v_units
   FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course;
  ELSE
   SELECT coalesce(jsonb_agg(jsonb_build_object('revisionId',revision_id,'revisionNumber',revision_number,
    'basedOnRevision',based_on_revision,'text',body_text,'recordedAt',recorded_at)
    ORDER BY revision_number),'[]'::jsonb) INTO v_units
   FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit
     AND EXISTS (SELECT 1 FROM atlas.teaching_course_units u WHERE u.unit_id=p_unit AND u.course_id=v_course);
  END IF;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_revision_read_v1',
   'courseId',v_course,'operation',p_operation,'unitId',p_unit,'revisionId',p_revision,
   'revisions',v_units);
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
AS $
DECLARE v_course uuid; v_auth uuid; v_person uuid; v_user uuid; v_title text; v_old text;
 v_latest integer; v_rev atlas.teaching_object_title_revisions%ROWTYPE;
 v_text text; v_members jsonb; v_current integer; v_unit atlas.teaching_course_units%ROWTYPE;
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
 IF p_operation IN ('course_title_save','unit_title_save') THEN
  v_title:=p_payload->>'title';
  IF v_title IS NULL OR v_title<>btrim(v_title) OR char_length(v_title) NOT BETWEEN 1 AND 150
  THEN RAISE EXCEPTION 'invalid title request' USING ERRCODE='22023'; END IF;
  IF p_operation='course_title_save' THEN
   SELECT name INTO v_old FROM atlas.teaching_courses WHERE id=v_course FOR UPDATE;
  ELSE
   SELECT title INTO v_old FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit FOR UPDATE;
   IF v_old IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
  END IF;
  IF v_old=v_title THEN RAISE EXCEPTION 'title must change' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_rev FROM atlas.teaching_object_title_revisions WHERE course_id=v_course AND request_id=p_request;
  IF v_rev.revision_id IS NOT NULL THEN
   IF v_rev.title IS DISTINCT FROM v_title OR v_rev.previous_title IS DISTINCT FROM v_old OR v_rev.object_id IS DISTINCT FROM CASE WHEN p_operation='course_title_save' THEN v_course ELSE p_unit END
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
 IF p_operation IN ('course_material_save','unit_subsection_save','revision_recover') THEN
  v_text:=p_payload->>'text';
  IF v_text IS NULL OR char_length(v_text)>40000 THEN RAISE EXCEPTION 'invalid manuscript request' USING ERRCODE='22023'; END IF;
  SELECT revision_id,revision_number,body_text INTO v_rev FROM atlas.teaching_course_manuscript_revisions WHERE course_id=v_course AND edit_request_id=p_request;
  IF v_rev.revision_id IS NOT NULL THEN
   IF v_rev.body_text IS DISTINCT FROM v_text OR v_rev.based_on_revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'replayed manuscript request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'requestId',p_request,'revisionNumber',v_rev.revision_number,'textLength',char_length(v_rev.body_text));
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
  PERFORM atlas.validate_course_composition_v1(v_course,v_members);
  SELECT coalesce(max(revision_number),0) INTO v_current FROM atlas.teaching_course_composition_revisions WHERE course_id=v_course;
  IF v_current<>p_expected_revision THEN RAISE EXCEPTION 'stale composition revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_composition_revisions(course_id,edit_request_id,based_on_revision,revision_number,members,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(v_course,p_request,v_current,v_current+1,v_members,v_person,v_user);
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,
   'courseId',v_course,'requestId',p_request,'revisionNumber',v_current+1,'members',v_members);
 END IF;
 IF p_operation='unit_move' THEN
  SELECT * INTO v_unit FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit FOR UPDATE;
  IF v_unit.unit_id IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
  UPDATE atlas.teaching_course_units SET display_position=display_position+1
   WHERE course_id=v_course AND display_position>=v_unit.display_position
   AND unit_id<>p_unit;
  UPDATE atlas.teaching_course_units SET display_position=(p_payload->>'position')::integer
   WHERE unit_id=p_unit;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,
   'courseId',v_course,'unitId',p_unit,'requestId',p_request,'position',(p_payload->>'position')::integer);
 END IF;
 RAISE EXCEPTION 'management write operation not admitted' USING ERRCODE='22023';
END $;
REVOKE ALL ON FUNCTION public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_management_write_service_v1(text,uuid,text,uuid,uuid,integer,jsonb)
 TO service_role;

COMMIT;
