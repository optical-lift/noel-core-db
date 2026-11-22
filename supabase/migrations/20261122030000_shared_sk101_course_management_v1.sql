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
 IF v_auth IS NULL OR NOT atlas.private_atlas_carrier_standing_grant_current_v1(v_auth)
 THEN RAISE EXCEPTION 'exact Course management grant required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations a
   WHERE a.id=v_auth AND a.authorization_state='active'
   AND a.allowed_command_keys @> ARRAY[p_command]::text[]
   AND a.denied_command_keys @> ARRAY[]::text[]
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
  SELECT public.shared_teaching_course_composition_read_self_api_v1(v_course) INTO v_last;
  RETURN v_last||jsonb_build_object('courseId',v_course);
 END IF;
 IF p_operation IN ('revision_history_read','revision_compare') THEN
  RETURN jsonb_build_object('contractVersion','atlas_course_management_revision_read_v1',
   'courseId',v_course,'operation',p_operation,'unitId',p_unit,'revisionId',p_revision);
 END IF;
 RAISE EXCEPTION 'management read operation not admitted' USING ERRCODE='22023';
END $$;

REVOKE ALL ON FUNCTION public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_management_read_service_v1(text,uuid,text,uuid,uuid,text)
 TO service_role;

COMMIT;
