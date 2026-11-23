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

CREATE FUNCTION atlas.sk101_compatible_management_peer_v1(p_id uuid,p_course uuid)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $$
 SELECT coalesce(p_course='2763f907-fdce-47d2-8308-3cd42c2d2e35'::uuid,false)
 AND EXISTS (
  SELECT 1 FROM atlas.delegated_agent_authorizations a
  WHERE a.id=p_id AND atlas.sk101_management_grant_current_v1(a.id,a.allowed_command_keys[1])
  AND NOT EXISTS (
   SELECT 1 FROM atlas.delegated_agent_authorizations x
   WHERE x.id<>a.id AND x.carrier_id=a.carrier_id AND x.principal_id=a.principal_id
   AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())
   AND x.allowed_command_keys && a.allowed_command_keys
  )
 );
$$;
REVOKE ALL ON FUNCTION atlas.sk101_compatible_management_peer_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.private_atlas_carrier_standing_grant_current_v1(p_authorization_id uuid)
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
   AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_versions pv WHERE pv.course_id=tc.id)
   AND titus.authoring_grant_current_active_v1(e.id)
   AND coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,'teaching.course.authoring.save_draft',1,
    jsonb_build_object('kind','teaching_course','id',tc.id::text))->>'allowed')::boolean,false)
   AND NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,'teaching.course.authoring.save_draft',1,
    jsonb_build_object('kind','teaching_course','id',tc.id::text))->>'confirmationRequired')::boolean,true)
   AND NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations x WHERE x.id<>a.id AND x.carrier_id=a.carrier_id
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())
     AND NOT atlas.sk101_compatible_management_peer_v1(x.id,tc.id))
 );
$function$;

CREATE OR REPLACE FUNCTION atlas.private_atlas_carrier_working_grant_current_v1(p_authorization_id uuid)
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
   AND a.purpose='Owner-approved private ChatGPT Course working draft'
   AND a.authorization_state='active' AND a.begins_at<=clock_timestamp()
   AND a.ends_at IS NOT NULL AND isfinite(a.ends_at) AND a.ends_at>clock_timestamp()
   AND a.ends_at<=a.begins_at+interval '24 hours'
   AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL AND a.max_execution_class='commit'
   AND a.allowed_command_keys=ARRAY['teaching.course.authoring.save_draft']
   AND a.denied_command_keys=ARRAY[]::text[]
   AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(tc.id::text))
   AND a.confirmation_policy='{"forceAllCommits":false}'::jsonb
   AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_versions pv WHERE pv.course_id=tc.id)
   AND titus.authoring_grant_current_active_v1(e.id)
   AND coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,'teaching.course.authoring.save_draft',1,
    jsonb_build_object('kind','teaching_course','id',tc.id::text))->>'allowed')::boolean,false)
   AND NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,'teaching.course.authoring.save_draft',1,
    jsonb_build_object('kind','teaching_course','id',tc.id::text))->>'confirmationRequired')::boolean,true)
   AND NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations x WHERE x.id<>a.id AND x.carrier_id=a.carrier_id
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())
     AND NOT atlas.sk101_compatible_management_peer_v1(x.id,tc.id))
 ) OR atlas.private_atlas_carrier_standing_grant_current_v1(p_authorization_id);
$function$;

CREATE OR REPLACE FUNCTION public.shared_private_atlas_carrier_enroll_standing_self_api_v1(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); pr atlas.principals%ROWTYPE; c atlas.delegated_agent_carriers%ROWTYPE; a atlas.delegated_agent_authorizations%ROWTYPE; ids uuid[]; aid uuid;
 scope_value jsonb:=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(p_course_id::text));
 policy_value jsonb:='{"forceAllCommits":false}'::jsonb;
BEGIN
 IF p_course_id IS NULL THEN
  RAISE EXCEPTION 'exact Course required' USING ERRCODE='22023'; END IF;
 SELECT * INTO pr FROM atlas.principals WHERE user_id=u AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active signed principal required' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM atlas.delegated_agent_carriers WHERE stable_key='chatgpt_atlas_private'
  AND status='active' AND carrier_kind='ai_agent' AND provider_key='openai'
  AND metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
  AND metadata->>'ownerPrincipalId'=pr.id::text FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'verified private carrier unavailable' USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,true);
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_courses WHERE id=p_course_id AND status='active' AND ledger_id IS NULL)
 THEN RAISE EXCEPTION 'active personal Course required' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_versions WHERE course_id=p_course_id)
 THEN RAISE EXCEPTION 'unpublished original required' USING ERRCODE='42501'; END IF;
 SELECT array_agg(id) INTO ids FROM atlas.delegated_agent_authorizations WHERE carrier_id=c.id AND principal_id=pr.id
  AND authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp())
  AND NOT atlas.sk101_compatible_management_peer_v1(id,p_course_id);
 IF coalesce(cardinality(ids),0)>1 THEN RAISE EXCEPTION 'multiple active delegations require review' USING ERRCODE='40001'; END IF;
 IF coalesce(cardinality(ids),0)=1 THEN
  SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=ids[1];
  IF a.ledger_id IS NOT NULL OR a.delegating_seat_id IS NOT NULL OR a.scope IS DISTINCT FROM scope_value
   OR a.confirmation_policy IS DISTINCT FROM policy_value OR a.allowed_command_keys IS DISTINCT FROM ARRAY['teaching.course.authoring.save_draft']
   OR a.denied_command_keys IS DISTINCT FROM ARRAY[]::text[] OR a.max_execution_class<>'commit'
   OR a.ends_at IS NOT NULL OR a.purpose IS DISTINCT FROM 'Owner-approved private ChatGPT Course standing draft' THEN
   RAISE EXCEPTION 'revoke existing delegation before creating another' USING ERRCODE='40001'; END IF;
  aid:=a.id;
 ELSE
  aid:=atlas.establish_delegated_agent_authorization_self_api_v1(c.id,NULL,NULL,'commit',
   ARRAY['teaching.course.authoring.save_draft'],ARRAY[]::text[],scope_value,policy_value,
   'Owner-approved private ChatGPT Course standing draft',NULL);
 END IF;
 IF NOT atlas.private_atlas_carrier_standing_grant_current_v1(aid)
 THEN RAISE EXCEPTION 'delegation authority unavailable' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_standing_enrollment_v1','authorizationId',aid,'courseId',p_course_id,
  'state','active','endsAt',NULL,'replayed',coalesce(cardinality(ids),0)=1);
END $function$;

CREATE OR REPLACE FUNCTION public.shared_private_atlas_carrier_enroll_working_self_api_v1(p_course_id uuid,p_ends_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $enroll$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); pr atlas.principals%ROWTYPE; c atlas.delegated_agent_carriers%ROWTYPE; a atlas.delegated_agent_authorizations%ROWTYPE; ids uuid[]; aid uuid;
 scope_value jsonb:=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(p_course_id::text));
 policy_value jsonb:='{"forceAllCommits":false}'::jsonb;
BEGIN
 IF p_course_id IS NULL OR p_ends_at IS NULL OR NOT isfinite(p_ends_at) OR p_ends_at<=clock_timestamp()
  OR p_ends_at>clock_timestamp()+interval '24 hours' THEN
  RAISE EXCEPTION 'exact Course and expiration within 24 hours required' USING ERRCODE='22023'; END IF;
 SELECT * INTO pr FROM atlas.principals WHERE user_id=u AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active signed principal required' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM atlas.delegated_agent_carriers WHERE stable_key='chatgpt_atlas_private'
  AND status='active' AND carrier_kind='ai_agent' AND provider_key='openai'
  AND metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
  AND metadata->>'ownerPrincipalId'=pr.id::text FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'verified private carrier unavailable' USING ERRCODE='42501'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,true);
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_courses WHERE id=p_course_id AND status='active' AND ledger_id IS NULL)
 THEN RAISE EXCEPTION 'active personal Course required' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_versions WHERE course_id=p_course_id)
 THEN RAISE EXCEPTION 'unpublished original required' USING ERRCODE='42501'; END IF;
 SELECT array_agg(id) INTO ids FROM atlas.delegated_agent_authorizations WHERE carrier_id=c.id AND principal_id=pr.id
  AND authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp())
  AND NOT atlas.sk101_compatible_management_peer_v1(id,p_course_id);
 IF coalesce(cardinality(ids),0)>1 THEN RAISE EXCEPTION 'multiple active delegations require review' USING ERRCODE='40001'; END IF;
 IF coalesce(cardinality(ids),0)=1 THEN
  SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=ids[1];
  IF a.ledger_id IS NOT NULL OR a.delegating_seat_id IS NOT NULL OR a.scope IS DISTINCT FROM scope_value
   OR a.confirmation_policy IS DISTINCT FROM policy_value OR a.allowed_command_keys IS DISTINCT FROM ARRAY['teaching.course.authoring.save_draft']
   OR a.denied_command_keys IS DISTINCT FROM ARRAY[]::text[] OR a.max_execution_class<>'commit'
   OR a.ends_at IS DISTINCT FROM p_ends_at THEN
   RAISE EXCEPTION 'revoke existing delegation before creating another' USING ERRCODE='40001'; END IF;
  aid:=a.id;
 ELSE
  aid:=atlas.establish_delegated_agent_authorization_self_api_v1(c.id,NULL,NULL,'commit',
   ARRAY['teaching.course.authoring.save_draft'],ARRAY[]::text[],scope_value,policy_value,
   'Owner-approved private ChatGPT Course working draft',p_ends_at);
 END IF;
 IF NOT atlas.private_atlas_carrier_working_grant_current_v1(aid)
 THEN RAISE EXCEPTION 'delegation authority unavailable' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_working_enrollment_v1','authorizationId',aid,'courseId',p_course_id,
  'state','active','endsAt',p_ends_at,'replayed',coalesce(cardinality(ids),0)=1);
END $enroll$;

CREATE FUNCTION atlas.sk101_management_admissible_v1(p_id uuid,p_command text)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path TO 'pg_catalog'
AS $$
 SELECT atlas.sk101_management_grant_current_v1(p_id,p_command)
 AND atlas.sk101_compatible_management_peer_v1(p_id,'2763f907-fdce-47d2-8308-3cd42c2d2e35')
 AND NOT EXISTS (
  SELECT 1 FROM atlas.delegated_agent_authorizations a
  JOIN atlas.delegated_agent_authorizations x ON x.carrier_id=a.carrier_id AND x.principal_id=a.principal_id
  WHERE a.id=p_id AND x.id<>a.id AND x.authorization_state='active'
  AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())
  AND NOT atlas.sk101_compatible_management_peer_v1(x.id,'2763f907-fdce-47d2-8308-3cd42c2d2e35')
  AND NOT (x.allowed_command_keys=ARRAY['teaching.course.authoring.save_draft']
   AND x.scope=a.scope AND atlas.private_atlas_carrier_working_grant_current_v1(x.id))
 );
$$;
REVOKE ALL ON FUNCTION atlas.sk101_management_admissible_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- Recheck authority inside the data transaction. Revocation takes an
-- exclusive lock on the same authorization before touching the credential.
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
 IF NOT FOUND OR NOT atlas.sk101_management_admissible_v1(aid,p_command) THEN RETURN false; END IF;
 SELECT * INTO cred FROM atlas.delegated_agent_credentials
 WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
 IF NOT FOUND OR cred.credential_state<>'active' OR cred.begins_at>clock_timestamp()
    OR cred.expires_at IS DISTINCT FROM grant_end OR cred.expires_at<=clock_timestamp()
    OR cred.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
    OR NOT atlas.sk101_management_admissible_v1(aid,p_command) THEN RETURN false; END IF;
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
 principal_id_value uuid; carrier_id_value uuid; aid uuid;
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
 SELECT a.id INTO aid FROM atlas.delegated_agent_authorizations a
 WHERE a.carrier_id=carrier_id_value AND a.principal_id=principal_id_value AND a.authorization_state='active'
 AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.allowed_command_keys=ARRAY[p_command]
 AND a.ends_at=p_ends_at AND atlas.sk101_compatible_management_peer_v1(a.id,p_course)
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
    'Owner-approved private ChatGPT SK 101 '||p_command,p_ends_at);
 END IF;
 IF NOT atlas.sk101_management_admissible_v1(aid,p_command) THEN
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
 IF NOT FOUND OR NOT atlas.sk101_management_admissible_v1(p_authorization,p_command) THEN
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
 WHERE a.created_by_user_id=signed_user AND atlas.sk101_management_admissible_v1(a.id,k.command);
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
