-- HELD clone candidate. Released legacy write and timed management fences remain intact.
BEGIN;

CREATE FUNCTION atlas.sk101_standing_management_grant_current_v1(p_authorization uuid,p_command text)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $$
 SELECT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 AND EXISTS (
  SELECT 1 FROM atlas.delegated_agent_authorizations a
  JOIN atlas.delegated_agent_carriers c ON c.id=a.carrier_id
  JOIN atlas.principals pr ON pr.id=a.principal_id AND pr.status='active'
  JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id AND b.binding_state='active' AND b.retired_at IS NULL
  JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
  JOIN atlas.teaching_courses tc ON tc.created_by_person_entity_id=e.id AND tc.status='active' AND tc.ledger_id IS NULL
  WHERE a.id=p_authorization
    AND tc.id='2763f907-fdce-47d2-8308-3cd42c2d2e35'
    AND e.id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'
    AND c.status='active' AND c.stable_key='chatgpt_atlas_private'
    AND c.provider_key='openai' AND c.carrier_kind='ai_agent'
    AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
    AND c.metadata->>'ownerPrincipalId'=pr.id::text
    AND a.created_by_user_id=pr.user_id AND a.basis->>'establishedBy'='principal_self_api'
    AND a.basis->>'userId'=pr.user_id::text
    AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL
    AND a.allowed_command_keys=ARRAY[p_command]
    AND a.denied_command_keys=ARRAY[]::text[]
    AND a.max_execution_class=CASE WHEN p_command='teaching.course.management.read' THEN 'read' ELSE 'commit' END
    AND a.authorization_state='active' AND a.begins_at<=clock_timestamp()
    AND a.ends_at IS NULL
    AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(tc.id::text))
    AND a.confirmation_policy='{"forceAllCommits":false}'::jsonb
    AND a.purpose='Owner-approved private ChatGPT SK 101 standing '||p_command
    AND titus.authoring_grant_current_active_v1(e.id)
 );
$$;

CREATE OR REPLACE FUNCTION atlas.sk101_compatible_management_peer_v1(p_id uuid,p_course uuid)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $$
 SELECT coalesce(p_course='2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid,false)
 AND EXISTS (
  SELECT 1 FROM atlas.delegated_agent_authorizations a
  WHERE a.id=p_id AND (atlas.sk101_management_grant_current_v1(a.id,a.allowed_command_keys[1])
    OR atlas.sk101_standing_management_grant_current_v1(a.id,a.allowed_command_keys[1]))
  AND NOT EXISTS (
   SELECT 1 FROM atlas.delegated_agent_authorizations x
   WHERE x.id<>a.id AND x.carrier_id=a.carrier_id AND x.principal_id=a.principal_id
   AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())
   AND x.allowed_command_keys && a.allowed_command_keys
  )
 );
$$;

CREATE FUNCTION atlas.sk101_standing_carrier_anchor_current_v1(p_authorization_id uuid)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT EXISTS(
  SELECT 1 FROM atlas.delegated_agent_authorizations a
  JOIN atlas.delegated_agent_carriers c ON c.id=a.carrier_id AND c.status='active'
  JOIN atlas.principals pr ON pr.id=a.principal_id AND pr.status='active'
  JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id AND b.binding_state='active' AND b.retired_at IS NULL
  JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
  JOIN atlas.teaching_courses tc ON tc.created_by_person_entity_id=e.id AND tc.status='active' AND tc.ledger_id IS NULL
  WHERE a.id=p_authorization_id
   AND c.stable_key='chatgpt_atlas_private' AND c.provider_key='openai' AND c.carrier_kind='ai_agent'
   AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
   AND c.metadata->>'ownerPrincipalId'=pr.id::text
   AND a.created_by_user_id=pr.user_id AND a.basis->>'establishedBy'='principal_self_api'
   AND a.basis->>'userId'=pr.user_id::text
   AND a.purpose='Owner-approved private ChatGPT Course standing draft'
   AND a.authorization_state='active' AND a.begins_at<=clock_timestamp()
   AND a.ends_at IS NULL
   AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL AND a.max_execution_class='commit'
   AND a.allowed_command_keys=ARRAY['teaching.course.authoring.save_draft']
   AND a.denied_command_keys=ARRAY[]::text[]
   AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(tc.id::text))
   AND a.confirmation_policy='{"forceAllCommits":false}'::jsonb
   AND tc.id='2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
   AND e.id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid
   AND titus.authoring_grant_current_active_v1(e.id)
 );
$function$;

CREATE FUNCTION public.shared_private_atlas_carrier_enroll_standing_management_self_api_v1(p_course uuid,p_command text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE signed_user uuid:=atlas.require_private_carrier_signed_user_v1();
 principal_id_value uuid; carrier_id_value uuid; aid uuid;
 replayed boolean; scope_value jsonb;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
 OR NOT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 THEN RAISE EXCEPTION 'exact management enrollment required' USING ERRCODE='22023'; END IF;
 SELECT pr.id INTO principal_id_value FROM atlas.principals pr
 JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id AND b.binding_state='active' AND b.retired_at IS NULL
 WHERE pr.user_id=signed_user AND pr.status='active' AND b.person_entity_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'
 FOR UPDATE OF pr;
 IF NOT FOUND THEN RAISE EXCEPTION 'signed owner required' USING ERRCODE='42501'; END IF;
 SELECT c.id INTO carrier_id_value FROM atlas.delegated_agent_carriers c
 WHERE c.stable_key='chatgpt_atlas_private' AND c.status='active' AND c.carrier_kind='ai_agent'
 AND c.provider_key='openai' AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
 AND c.metadata->>'ownerPrincipalId'=principal_id_value::text FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'exact carrier required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course,true);
 scope_value:=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(p_course::text));
 SELECT a.id INTO aid FROM atlas.delegated_agent_authorizations a
 WHERE a.carrier_id=carrier_id_value AND a.principal_id=principal_id_value AND a.authorization_state='active'
 AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.allowed_command_keys=ARRAY[p_command]
 AND a.ends_at IS NULL AND atlas.sk101_compatible_management_peer_v1(a.id,p_course)
 FOR UPDATE;
 replayed:=FOUND;
 IF NOT replayed AND EXISTS (
  SELECT 1 FROM atlas.delegated_agent_authorizations a WHERE a.carrier_id=carrier_id_value
  AND a.principal_id=principal_id_value AND a.authorization_state='active'
  AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.allowed_command_keys && ARRAY[p_command]
 ) THEN
  RAISE EXCEPTION 'current management enrollment differs' USING ERRCODE='40001';
 END IF;
 IF NOT replayed THEN
  aid:=atlas.establish_delegated_agent_authorization_self_api_v1(carrier_id_value,NULL,NULL,
    CASE WHEN p_command='teaching.course.management.read' THEN 'read' ELSE 'commit' END,
    ARRAY[p_command],ARRAY[]::text[],scope_value,'{"forceAllCommits":false}'::jsonb,
    'Owner-approved private ChatGPT SK 101 standing '||p_command,NULL);
 END IF;
 IF NOT (atlas.sk101_standing_management_grant_current_v1(aid,p_command)
   AND atlas.sk101_compatible_management_peer_v1(aid,p_course)) THEN
  RAISE EXCEPTION 'management enrollment unavailable' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('authorizationId',aid,'courseId',p_course,'command',p_command,'endsAt',NULL,'replayed',replayed);
END;
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_revoke_standing_management_self_api_v1(p_authorization uuid,p_command text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE signed_user uuid:=atlas.require_private_carrier_signed_user_v1(); pr_id uuid;
BEGIN
 IF NOT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 THEN RAISE EXCEPTION 'exact management command required' USING ERRCODE='22023'; END IF;
 SELECT pr.id INTO pr_id FROM atlas.principals pr
 JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id AND b.binding_state='active' AND b.retired_at IS NULL
 WHERE pr.user_id=signed_user AND pr.status='active' AND b.person_entity_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'
 FOR UPDATE OF pr;
 IF NOT FOUND THEN RAISE EXCEPTION 'signed owner required' USING ERRCODE='42501'; END IF;
 PERFORM a.id FROM atlas.delegated_agent_authorizations a
 JOIN atlas.delegated_agent_carriers c ON c.id=a.carrier_id
 WHERE a.id=p_authorization AND a.principal_id=pr_id AND a.created_by_user_id=signed_user
 AND c.stable_key='chatgpt_atlas_private' AND c.metadata->>'ownerPrincipalId'=pr_id::text
 AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
 AND a.allowed_command_keys=ARRAY[p_command] AND a.ends_at IS NULL AND a.purpose='Owner-approved private ChatGPT SK 101 standing '||p_command
 AND a.scope='{"targetKinds":["teaching_course"],"targetIds":["2763f907-fdce-47d2-8308-3cd42c2d2e35"]}'::jsonb
 FOR UPDATE OF a;
 IF NOT FOUND THEN RAISE EXCEPTION 'owned management grant required' USING ERRCODE='42501'; END IF;
 RETURN atlas.revoke_delegated_agent_authorization_self_api_v1(p_authorization,'Principal revoked exact SK 101 management authority');
END;
$$;


CREATE FUNCTION atlas.sk101_lock_standing_management_v1(p_token_hash text,p_course uuid,p_command text,p_admission boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $$
DECLARE anchor atlas.delegated_agent_authorizations%ROWTYPE; grant_id uuid;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
 OR NOT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;

 -- Lock authorization rows before credential, consistently with revocation.
 SELECT a.* INTO anchor FROM atlas.delegated_agent_authorizations a
 JOIN atlas.delegated_agent_credentials c ON c.authorization_id=a.id
 WHERE c.token_hash=p_token_hash AND atlas.sk101_standing_carrier_anchor_current_v1(a.id)
 FOR SHARE OF a;
 IF NOT FOUND THEN RETURN false; END IF;

 SELECT a.id INTO grant_id FROM atlas.delegated_agent_authorizations a
 WHERE a.principal_id=anchor.principal_id AND a.carrier_id=anchor.carrier_id
 AND atlas.sk101_standing_management_grant_current_v1(a.id,p_command)
 AND atlas.sk101_compatible_management_peer_v1(a.id,p_course)
 FOR SHARE OF a;
 IF NOT FOUND THEN RETURN false; END IF;

 IF p_admission THEN
  PERFORM 1 FROM atlas.delegated_agent_credentials c
 WHERE c.authorization_id=anchor.id AND c.token_hash=p_token_hash
 AND c.credential_state='active' AND c.begins_at<=clock_timestamp() AND c.expires_at IS NULL
 AND c.metadata->>'privateCarrierCredentialV1'='true' FOR NO KEY UPDATE;
 ELSE
  PERFORM 1 FROM atlas.delegated_agent_credentials c
 WHERE c.authorization_id=anchor.id AND c.token_hash=p_token_hash
 AND c.credential_state='active' AND c.begins_at<=clock_timestamp() AND c.expires_at IS NULL
 AND c.metadata->>'privateCarrierCredentialV1'='true' FOR SHARE;
 END IF;
 RETURN FOUND AND atlas.sk101_standing_carrier_anchor_current_v1(anchor.id)
  AND atlas.sk101_standing_management_grant_current_v1(grant_id,p_command)
  AND atlas.sk101_compatible_management_peer_v1(grant_id,p_course);
END;
$$;

REVOKE ALL ON FUNCTION atlas.sk101_standing_management_grant_current_v1(uuid,text),
 atlas.sk101_standing_carrier_anchor_current_v1(uuid),
 atlas.sk101_lock_standing_management_v1(text,uuid,text,boolean),
 public.shared_private_atlas_carrier_enroll_standing_management_self_api_v1(uuid,text),
 public.shared_private_atlas_carrier_revoke_standing_management_self_api_v1(uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_enroll_standing_management_self_api_v1(uuid,text),
 public.shared_private_atlas_carrier_revoke_standing_management_self_api_v1(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.require_private_course_management_v1(
 p_token_hash text,p_course uuid,p_command text,p_write boolean
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE aid uuid; grant_end timestamptz;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
 OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
 OR NOT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 OR p_write IS DISTINCT FROM (p_command='teaching.course.management.write')
 THEN RAISE EXCEPTION 'exact Course management grant required' USING ERRCODE='42501'; END IF;
 IF atlas.sk101_lock_standing_management_v1(p_token_hash,p_course,p_command,false) THEN
  RETURN p_course;
 END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 SELECT ends_at INTO grant_end FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.sk101_management_admissible_v1(aid,p_command)
 THEN RAISE EXCEPTION 'current management grant required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.delegated_agent_credentials c
 WHERE c.authorization_id=aid AND c.token_hash=p_token_hash AND c.credential_state='active'
 AND c.begins_at<=clock_timestamp() AND c.expires_at=grant_end AND c.expires_at>clock_timestamp()
 AND c.metadata->>'privateCarrierCredentialV1'='true' FOR SHARE;
 IF NOT FOUND OR NOT atlas.sk101_management_admissible_v1(aid,p_command)
 THEN RAISE EXCEPTION 'current management credential required' USING ERRCODE='42501'; END IF;
 RETURN p_course;
END;
$$;

CREATE OR REPLACE FUNCTION public.shared_private_atlas_carrier_admit_management_service_v1(p_token_hash text,p_command text,p_course uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE aid uuid; cred atlas.delegated_agent_credentials%ROWTYPE;
        grant_end timestamptz; minute_id bigint; used int:=0; previous jsonb;
        bucket text;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
    OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 IF atlas.sk101_lock_standing_management_v1(p_token_hash,p_course,p_command,true) THEN
  SELECT * INTO STRICT cred FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 ELSE
  SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
  IF aid IS NULL THEN RETURN false; END IF;
  SELECT ends_at INTO grant_end FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
  IF NOT FOUND OR NOT atlas.sk101_management_admissible_v1(aid,p_command) THEN RETURN false; END IF;
  SELECT * INTO cred FROM atlas.delegated_agent_credentials
  WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
  IF NOT FOUND OR cred.credential_state<>'active' OR cred.begins_at>clock_timestamp()
     OR cred.expires_at IS DISTINCT FROM grant_end OR cred.expires_at<=clock_timestamp()
     OR cred.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
     OR NOT atlas.sk101_management_admissible_v1(aid,p_command) THEN RETURN false; END IF;
 END IF;
 minute_id:=floor(extract(epoch FROM clock_timestamp())/60)::bigint;
 bucket:=CASE WHEN cred.expires_at IS NULL THEN 'privateCarrierStandingManagementAdmissionV1'
              ELSE 'privateCarrierAdmissionV1' END;
 previous:=cred.metadata->bucket;
 IF previous IS NOT NULL THEN
  IF jsonb_typeof(previous)<>'object' OR coalesce(previous->>'window','') !~ '^[0-9]{1,18}$'
     OR coalesce(previous->>'count','') !~ '^[0-9]{1,2}$' THEN RETURN false; END IF;
  IF (previous->>'window')::bigint>minute_id THEN RETURN false; END IF;
  IF (previous->>'window')::bigint=minute_id THEN used:=(previous->>'count')::int; END IF;
 END IF;
 IF used>=12 THEN RETURN false; END IF;
 UPDATE atlas.delegated_agent_credentials SET metadata=jsonb_set(metadata,ARRAY[bucket],
   jsonb_build_object('window',minute_id,'count',used+1),true) WHERE id=cred.id;
 RETURN true;
END;
$$;

CREATE TABLE atlas.sk101_composition_removal_confirmations (
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id),
 request_id uuid NOT NULL,
 base_revision integer NOT NULL CHECK (base_revision > 0),
 members jsonb NOT NULL,
 owner_user_id uuid NOT NULL,
 PRIMARY KEY (course_id,request_id)
);
ALTER TABLE atlas.sk101_composition_removal_confirmations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.sk101_composition_removal_confirmations FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.sk101_composition_removes_members_v1(p_course uuid,p_revision integer,p_members jsonb)
RETURNS boolean LANGUAGE sql SET search_path TO 'pg_catalog'
AS $$
 SELECT EXISTS (
  SELECT 1 FROM atlas.teaching_course_composition_revisions r
  CROSS JOIN LATERAL jsonb_array_elements(r.members) AS old(member)
  WHERE r.course_id=p_course AND r.revision_number=p_revision
  AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_members) AS proposed(member)
                  WHERE proposed.member=old.member)
 );
$$;
REVOKE ALL ON FUNCTION atlas.sk101_composition_removes_members_v1(uuid,integer,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_sk101_confirm_composition_removal_self_api_v1(
 p_course uuid,p_request uuid,p_base_revision integer,p_members jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE signed_user uuid:=atlas.require_private_carrier_signed_user_v1(); current_revision integer;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
 OR p_request IS NULL OR p_base_revision IS NULL OR p_base_revision<=0
 THEN RAISE EXCEPTION 'exact composition request required' USING ERRCODE='22023'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course,true);
 PERFORM 1 FROM reality.auth_person_bindings b
 WHERE b.auth_user_id=signed_user AND b.binding_state='active' AND b.retired_at IS NULL
 AND b.person_entity_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'signed SK 101 owner required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.teaching_courses WHERE id=p_course FOR UPDATE;
 SELECT coalesce(max(revision_number),0) INTO current_revision
 FROM atlas.teaching_course_composition_revisions WHERE course_id=p_course;
 IF current_revision<>p_base_revision THEN RAISE EXCEPTION 'stale composition revision' USING ERRCODE='40001'; END IF;
 PERFORM atlas.validate_course_composition_v1(p_course,p_members);
 IF NOT atlas.sk101_composition_removes_members_v1(p_course,current_revision,p_members)
 THEN RAISE EXCEPTION 'composition removal required' USING ERRCODE='22023'; END IF;
 INSERT INTO atlas.sk101_composition_removal_confirmations(course_id,request_id,base_revision,members,owner_user_id)
 VALUES(p_course,p_request,p_base_revision,p_members,signed_user) ON CONFLICT DO NOTHING;
 IF NOT EXISTS (SELECT 1 FROM atlas.sk101_composition_removal_confirmations c
   WHERE c.course_id=p_course AND c.request_id=p_request AND c.base_revision=p_base_revision
   AND c.members=p_members AND c.owner_user_id=signed_user)
 THEN RAISE EXCEPTION 'replayed confirmation differs' USING ERRCODE='23505'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.shared_sk101_confirm_composition_removal_self_api_v1(uuid,uuid,integer,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_sk101_confirm_composition_removal_self_api_v1(uuid,uuid,integer,jsonb) TO authenticated;

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
 PERFORM 1 FROM atlas.teaching_courses WHERE id=v_course FOR UPDATE;
 IF p_operation IN ('unit_title_save','unit_move','unit_subsection_save','revision_recover') THEN
  SELECT * INTO v_unit FROM atlas.teaching_course_units WHERE course_id=v_course AND unit_id=p_unit FOR UPDATE;
  IF v_unit.unit_id IS NULL THEN RAISE EXCEPTION 'authorized Unit required' USING ERRCODE='42501'; END IF;
 END IF;
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
  IF v_start<0 OR v_end<v_start OR v_end>char_length(v_base_text)
  THEN RAISE EXCEPTION 'invalid Unit subsection selection' USING ERRCODE='22023'; END IF;
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
  SELECT coalesce(max(revision_number),0) INTO v_latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit;
  SELECT body_text INTO v_current_text FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit ORDER BY revision_number DESC LIMIT 1;
  v_current_text:=coalesce(v_current_text,'');
  IF v_latest<>p_expected_revision THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  IF v_base_text IS DISTINCT FROM v_current_text
  THEN RAISE EXCEPTION 'stale Unit subsection source' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(p_unit,p_request,v_latest,v_latest+1,v_text,v_person,v_user) RETURNING * INTO v_prior_unit;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'textLength',char_length(v_text));
 END IF; IF p_operation='revision_recover' THEN
  IF p_payload ? 'text' OR NOT (p_payload ? 'revisionId')
  THEN RAISE EXCEPTION 'historical source revision required' USING ERRCODE='22023'; END IF;
  v_source_revision:=(p_payload->>'revisionId')::uuid;
  SELECT r.* INTO v_source_unit_revision FROM atlas.teaching_course_unit_revisions r
   JOIN atlas.teaching_course_units u ON u.unit_id=r.unit_id AND u.course_id=v_course
   WHERE r.unit_id=p_unit AND r.revision_id=v_source_revision;
  IF v_source_unit_revision.revision_id IS NULL THEN RAISE EXCEPTION 'historical source revision not found' USING ERRCODE='42501'; END IF;
  v_text:=v_source_unit_revision.body_text;
  SELECT * INTO v_prior_unit FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit AND edit_request_id=p_request;
  IF v_prior_unit.revision_id IS NOT NULL THEN
   IF v_prior_unit.body_text IS DISTINCT FROM v_text OR v_prior_unit.based_on_revision IS DISTINCT FROM p_expected_revision
      OR v_prior_unit.recorded_by_person_entity_id IS DISTINCT FROM v_person OR v_prior_unit.recorded_by_auth_user_id IS DISTINCT FROM v_user
      OR v_prior_unit.recovered_from_revision_id IS DISTINCT FROM v_source_revision
   THEN RAISE EXCEPTION 'replayed recovery request differs' USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'sourceRevisionId',v_source_revision,'textLength',char_length(v_prior_unit.body_text));
  END IF;
  SELECT coalesce(max(revision_number),0) INTO v_latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=p_unit;
  IF v_latest<>p_expected_revision THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,recovered_from_revision_id,recorded_by_person_entity_id,recorded_by_auth_user_id)
   VALUES(p_unit,p_request,v_latest,v_latest+1,v_text,v_source_revision,v_person,v_user) RETURNING * INTO v_prior_unit;
  RETURN jsonb_build_object('contractVersion','atlas_course_management_write_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_unit.revision_id,'revisionNumber',v_prior_unit.revision_number,'sourceRevisionId',v_source_revision,'textLength',char_length(v_text));
 END IF; IF p_operation='course_material_save' THEN
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
  IF atlas.sk101_composition_removes_members_v1(v_course,v_current,v_members)
   AND NOT EXISTS (SELECT 1 FROM atlas.sk101_composition_removal_confirmations c
    WHERE c.course_id=v_course AND c.request_id=p_request AND c.base_revision=v_current
    AND c.members=v_members AND c.owner_user_id=v_user)
  THEN RAISE EXCEPTION 'signed confirmation required for exact composition removal' USING ERRCODE='42501'; END IF;
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
  RETURN jsonb_build_object('contractVersion','atlas_course_management_order_receipt_v1','operation',p_operation,'courseId',v_course,'unitId',p_unit,'requestId',p_request,'revisionId',v_prior_order.revision_id,'revisionNumber',v_prior_order.revision_number,'position',v_position,'ordering',v_ordering);
 END IF;
 RAISE EXCEPTION 'management write operation not admitted' USING ERRCODE='22023';
END $$;
COMMIT;
