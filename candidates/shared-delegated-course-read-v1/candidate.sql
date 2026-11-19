-- HELD source candidate. No live migration, grant, credential, or Course data write.
-- Reuse the current exact working-draft grant for read access to its one Course.
-- A durable revocable grant is a separate authority change.
BEGIN;

CREATE FUNCTION atlas.require_private_course_read_grant_v1(p_token_hash text, p_course uuid)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $read_grant$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE;
        c atlas.delegated_agent_credentials%ROWTYPE;
        aid uuid;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' OR p_course IS NULL THEN
  RAISE EXCEPTION 'exact Course read grant required' USING ERRCODE='42501';
 END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF aid IS NULL THEN
  RAISE EXCEPTION 'exact Course read grant required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_working_grant_current_v1(aid)
   OR a.scope IS DISTINCT FROM jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),
                                                  'targetIds',jsonb_build_array(p_course::text)) THEN
  RAISE EXCEPTION 'exact Course read grant required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO c FROM atlas.delegated_agent_credentials
  WHERE token_hash=p_token_hash AND authorization_id=aid FOR SHARE;
 IF NOT FOUND OR c.credential_state<>'active' OR c.begins_at>clock_timestamp()
  OR c.expires_at IS NULL OR c.expires_at<=clock_timestamp()
  OR c.expires_at IS DISTINCT FROM a.ends_at
  OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
  OR NOT atlas.private_atlas_carrier_working_grant_current_v1(aid) THEN
  RAISE EXCEPTION 'exact Course read grant required' USING ERRCODE='42501';
 END IF;
 RETURN p_course;
END $read_grant$;

CREATE FUNCTION atlas.read_private_course_outline_service_v1(p_token_hash text, p_course uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $outline$
DECLARE v_course uuid; v_units jsonb;
BEGIN
 v_course:=atlas.require_private_course_read_grant_v1(p_token_hash,p_course);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'unitId',u.unit_id,'kind',u.kind,'title',u.title,
  'position',u.display_position,'createdAt',u.created_at)
   ORDER BY u.display_position,u.unit_id),'[]'::jsonb)
 INTO v_units FROM atlas.teaching_course_units u WHERE u.course_id=v_course;
 RETURN jsonb_build_object('contractVersion','shared_teaching_course_outline_v1',
                           'courseId',v_course,'units',v_units);
END $outline$;

CREATE FUNCTION atlas.read_private_course_unit_service_v1(p_token_hash text, p_course uuid, p_unit uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $unit$
DECLARE v_course uuid;
        v_unit atlas.teaching_course_units%ROWTYPE;
        v_revision atlas.teaching_course_unit_revisions%ROWTYPE;
BEGIN
 v_course:=atlas.require_private_course_read_grant_v1(p_token_hash,p_course);
 IF p_unit IS NULL THEN
  RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_unit FROM atlas.teaching_course_units
  WHERE unit_id=p_unit AND course_id=v_course;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_revision FROM atlas.teaching_course_unit_revisions
  WHERE unit_id=v_unit.unit_id ORDER BY revision_number DESC LIMIT 1;
 RETURN jsonb_build_object(
  'contractVersion','shared_teaching_course_unit_material_v1',
  'courseId',v_course,
  'unit',jsonb_build_object('unitId',v_unit.unit_id,'kind',v_unit.kind,'title',v_unit.title,
                            'position',v_unit.display_position,'createdAt',v_unit.created_at),
  'material',CASE WHEN v_revision.revision_id IS NULL THEN NULL ELSE
   jsonb_build_object('revisionId',v_revision.revision_id,
                      'revisionNumber',v_revision.revision_number,
                      'text',v_revision.body_text,'savedAt',v_revision.recorded_at) END);
END $unit$;

CREATE FUNCTION public.shared_delegated_course_outline_read_service_v1(p_token_hash text,p_course uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog AS $outline_facade$
 SELECT atlas.read_private_course_outline_service_v1(p_token_hash,p_course);
$outline_facade$;

CREATE FUNCTION public.shared_delegated_course_unit_read_service_v1(p_token_hash text,p_course uuid,p_unit uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog AS $unit_facade$
 SELECT atlas.read_private_course_unit_service_v1(p_token_hash,p_course,p_unit);
$unit_facade$;

REVOKE ALL ON FUNCTION atlas.require_private_course_read_grant_v1(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.read_private_course_outline_service_v1(text,uuid),
 atlas.read_private_course_unit_service_v1(text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.read_private_course_outline_service_v1(text,uuid),
 atlas.read_private_course_unit_service_v1(text,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.shared_delegated_course_outline_read_service_v1(text,uuid),
 public.shared_delegated_course_unit_read_service_v1(text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_outline_read_service_v1(text,uuid),
 public.shared_delegated_course_unit_read_service_v1(text,uuid,uuid) TO service_role;
COMMIT;
