-- Partial held candidate. Never apply directly to a hosted database.
BEGIN;

CREATE FUNCTION atlas.sk101_management_grant_current_v1(p_authorization uuid,p_command text)
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
    AND a.ends_at IS NOT NULL AND isfinite(a.ends_at)
    AND a.ends_at>clock_timestamp() AND a.ends_at<=a.begins_at+interval '24 hours'
    AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(tc.id::text))
    AND a.confirmation_policy='{"forceAllCommits":false}'::jsonb
    AND a.purpose='Owner-approved private ChatGPT SK 101 '||p_command
    AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_versions v WHERE v.course_id=tc.id)
    AND titus.authoring_grant_current_active_v1(e.id)
 );
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_admit_management_service_v1(p_token_hash text,p_command text,p_course uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE aid uuid; cred atlas.delegated_agent_credentials%ROWTYPE;
        grant_end timestamptz; minute_id bigint; used int:=0; previous jsonb;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
    OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF aid IS NULL THEN RETURN false; END IF;
 SELECT ends_at INTO grant_end FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.sk101_management_grant_current_v1(aid,p_command) THEN RETURN false; END IF;
 SELECT * INTO cred FROM atlas.delegated_agent_credentials
 WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
 IF NOT FOUND OR cred.credential_state<>'active' OR cred.begins_at>clock_timestamp()
    OR cred.expires_at IS DISTINCT FROM grant_end OR cred.expires_at<=clock_timestamp()
    OR cred.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
    OR NOT atlas.sk101_management_grant_current_v1(aid,p_command) THEN RETURN false; END IF;
 minute_id:=floor(extract(epoch FROM clock_timestamp())/60)::bigint;
 previous:=cred.metadata->'privateCarrierAdmissionV1';
 IF previous IS NOT NULL THEN
  IF jsonb_typeof(previous)<>'object' OR coalesce(previous->>'window','') !~ '^[0-9]{1,18}$'
     OR coalesce(previous->>'count','') !~ '^[0-9]{1,2}$' THEN RETURN false; END IF;
  IF (previous->>'window')::bigint>minute_id THEN RETURN false; END IF;
  IF (previous->>'window')::bigint=minute_id THEN used:=(previous->>'count')::int; END IF;
 END IF;
 IF used>=12 THEN RETURN false; END IF;
 UPDATE atlas.delegated_agent_credentials SET metadata=jsonb_set(metadata,'{privateCarrierAdmissionV1}',
   jsonb_build_object('window',minute_id,'count',used+1),true) WHERE id=cred.id;
 RETURN true;
END;
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_enroll_management_self_api_v1(p_course uuid,p_command text,p_ends_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE signed_user uuid:=atlas.require_private_carrier_signed_user_v1();
 principal_id_value uuid; carrier_id_value uuid; aid uuid; existing_end timestamptz;
 replayed boolean; scope_value jsonb;
BEGIN
 IF p_course IS DISTINCT FROM '2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid
 OR NOT coalesce(p_command IN ('teaching.course.management.read','teaching.course.management.write'),false)
 OR p_ends_at IS NULL OR NOT isfinite(p_ends_at) OR p_ends_at<=clock_timestamp()
 OR p_ends_at>clock_timestamp()+interval '24 hours'
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
 SELECT a.id,a.ends_at INTO aid,existing_end FROM atlas.delegated_agent_authorizations a
 WHERE a.carrier_id=carrier_id_value AND a.principal_id=principal_id_value AND a.authorization_state='active'
 AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.allowed_command_keys @> ARRAY[p_command]
 FOR UPDATE;
 replayed:=FOUND;
 IF replayed AND existing_end IS DISTINCT FROM p_ends_at THEN
  RAISE EXCEPTION 'current management enrollment differs' USING ERRCODE='40001';
 END IF;
 IF NOT replayed THEN
  aid:=atlas.establish_delegated_agent_authorization_self_api_v1(carrier_id_value,NULL,NULL,
    CASE WHEN p_command='teaching.course.management.read' THEN 'read' ELSE 'commit' END,
    ARRAY[p_command],ARRAY[]::text[],scope_value,'{"forceAllCommits":false}'::jsonb,
    'Owner-approved private ChatGPT SK 101 '||p_command,p_ends_at);
 END IF;
 IF NOT atlas.sk101_management_grant_current_v1(aid,p_command) THEN
  RAISE EXCEPTION 'management enrollment unavailable' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('authorizationId',aid,'courseId',p_course,'command',p_command,'endsAt',p_ends_at,'replayed',replayed);
END;
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_issue_management_service_v1(p_authorization uuid,p_command text,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE;
 c atlas.delegated_agent_credentials%ROWTYPE; cid uuid; replayed boolean;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'canonical credential hash required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=p_authorization FOR UPDATE;
 IF NOT FOUND OR NOT atlas.sk101_management_grant_current_v1(p_authorization,p_command) THEN
  RAISE EXCEPTION 'current exact management grant required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO c FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 replayed:=FOUND;
 IF replayed THEN
  IF c.authorization_id<>a.id OR c.credential_state<>'active' OR c.begins_at>clock_timestamp()
     OR c.expires_at IS DISTINCT FROM a.ends_at OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'credential identity mismatch' USING ERRCODE='42501'; END IF;
  cid:=c.id;
 ELSE
  IF EXISTS(SELECT 1 FROM atlas.delegated_agent_credentials WHERE authorization_id=a.id AND credential_state='active'
    AND (expires_at IS NULL OR expires_at>clock_timestamp()))
  THEN RAISE EXCEPTION 'revoke current management grant before reissuing' USING ERRCODE='40001'; END IF;
  cid:=atlas.issue_delegated_agent_credential_service_v1(a.id,p_token_hash,a.ends_at,'{"privateCarrierCredentialV1":true}'::jsonb);
 END IF;
 RETURN jsonb_build_object('authorizationId',a.id,'command',p_command,'credentialId',cid,'expiresAt',a.ends_at,'replayed',replayed);
END;
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_management_status_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $$
DECLARE signed_user uuid:=atlas.require_private_carrier_signed_user_v1(); grants jsonb;
BEGIN
 SELECT coalesce(jsonb_agg(jsonb_build_object('authorizationId',a.id,'command',k.command,
  'endsAt',a.ends_at,'credentialId',cred.id,'credentialExpiresAt',cred.expires_at)
  ORDER BY k.command),'[]'::jsonb) INTO grants
 FROM atlas.delegated_agent_authorizations a
 CROSS JOIN LATERAL unnest(a.allowed_command_keys) k(command)
 LEFT JOIN atlas.delegated_agent_credentials cred ON cred.authorization_id=a.id
  AND cred.credential_state='active' AND cred.begins_at<=clock_timestamp()
  AND cred.expires_at=a.ends_at AND cred.expires_at>clock_timestamp()
  AND cred.metadata->>'privateCarrierCredentialV1'='true'
 WHERE a.created_by_user_id=signed_user AND atlas.sk101_management_grant_current_v1(a.id,k.command);
 RETURN jsonb_build_object('courseId','2763f907-fdce-47d2-8308-3cd42c2d2e35','authorizations',grants);
END;
$$;

CREATE FUNCTION public.shared_private_atlas_carrier_revoke_management_self_api_v1(p_authorization uuid,p_command text)
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
 AND a.allowed_command_keys=ARRAY[p_command] AND a.purpose='Owner-approved private ChatGPT SK 101 '||p_command
 AND a.scope='{"targetKinds":["teaching_course"],"targetIds":["2763f907-fdce-47d2-8308-3cd42c2d2e35"]}'::jsonb
 FOR UPDATE OF a;
 IF NOT FOUND THEN RAISE EXCEPTION 'owned management grant required' USING ERRCODE='42501'; END IF;
 RETURN atlas.revoke_delegated_agent_authorization_self_api_v1(p_authorization,'Principal revoked exact SK 101 management authority');
END;
$$;

REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_management_status_self_api_v1(),public.shared_private_atlas_carrier_revoke_management_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_management_status_self_api_v1(),public.shared_private_atlas_carrier_revoke_management_self_api_v1(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_enroll_management_self_api_v1(uuid,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_enroll_management_self_api_v1(uuid,text,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_issue_management_service_v1(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_issue_management_service_v1(uuid,text,text) TO service_role;
REVOKE ALL ON FUNCTION atlas.sk101_management_grant_current_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_admit_management_service_v1(text,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_admit_management_service_v1(text,text,uuid) TO service_role;
COMMIT;
