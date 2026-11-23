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
COMMIT;
