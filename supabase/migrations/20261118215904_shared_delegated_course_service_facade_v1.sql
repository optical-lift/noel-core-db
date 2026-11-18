-- HELD: Atlas service-only transport facade. No carrier, credential or grant rows.
BEGIN;
CREATE FUNCTION public.shared_delegated_course_prepare_service_v1(p_token_hash text,p_course uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog
AS $prepare$ SELECT atlas.prepare_course_authoring_proposal_service_v1(p_token_hash,p_course,p_proposal); $prepare$;
CREATE FUNCTION public.shared_delegated_course_apply_service_v1(p_token_hash text,p_invocation uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog
AS $apply$ SELECT atlas.apply_course_authoring_proposal_service_v1(p_token_hash,p_invocation,p_proposal); $apply$;
REVOKE ALL ON FUNCTION public.shared_delegated_course_prepare_service_v1(text,uuid,jsonb), public.shared_delegated_course_apply_service_v1(text,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_prepare_service_v1(text,uuid,jsonb), public.shared_delegated_course_apply_service_v1(text,uuid,jsonb) TO service_role;

-- Signed owner-private enrollment. No credential is created by a signed
-- call. The existing carrier operator must independently establish verified
-- plugin custody and bind the carrier's metadata to its one principal.
CREATE FUNCTION atlas.require_private_carrier_signed_user_v1()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $session$
DECLARE u uuid:=auth.uid(); sid text:=auth.jwt()->>'session_id';
BEGIN
 IF u IS NULL OR coalesce(auth.jwt()->>'is_anonymous','false')='true'
  OR sid IS NULL OR sid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RAISE EXCEPTION 'current signed session required' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.sessions WHERE id=sid::uuid AND user_id=u
  AND (not_after IS NULL OR not_after>clock_timestamp()))
 THEN RAISE EXCEPTION 'current signed session required' USING ERRCODE='42501'; END IF;
 RETURN u;
END $session$;
REVOKE ALL ON FUNCTION atlas.require_private_carrier_signed_user_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Return only the current caller's own private connection, not a provider
-- directory or credential/hash. Revocation remains available if the Course
-- authoring grant or the carrier's operational status subsequently ends.
CREATE FUNCTION public.shared_private_atlas_carrier_status_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $status$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); c atlas.delegated_agent_carriers%ROWTYPE; a atlas.delegated_agent_authorizations%ROWTYPE; pid uuid; courses jsonb:='[]'; person uuid;
BEGIN
 SELECT id INTO pid FROM atlas.principals WHERE user_id=u;
 IF pid IS NULL THEN RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v1','carrierReady',false,'courses',courses,'authorization',NULL); END IF;
 SELECT * INTO c FROM atlas.delegated_agent_carriers WHERE stable_key='chatgpt_atlas_private'
  AND provider_key='openai' AND carrier_kind='ai_agent'
  AND metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
  AND metadata->>'ownerPrincipalId'=pid::text;
 IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v1','carrierReady',false,'courses',courses,'authorization',NULL); END IF;
 IF c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active') THEN
  SELECT b.person_entity_id INTO person FROM reality.auth_person_bindings b
   JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
   WHERE b.auth_user_id=u AND b.binding_state='active' AND b.retired_at IS NULL;
  IF person IS NOT NULL AND titus.authoring_grant_current_active_v1(person) THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('courseId',s.id,'title',s.title) ORDER BY s.title,s.id),'[]'::jsonb)
    INTO courses FROM (SELECT id,name AS title FROM atlas.teaching_courses WHERE created_by_person_entity_id=person AND status='active' AND ledger_id IS NULL ORDER BY name,id LIMIT 100) s;
  END IF;
 END IF;
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE principal_id=pid AND carrier_id=c.id
  AND ledger_id IS NULL AND delegating_seat_id IS NULL AND allowed_command_keys=ARRAY['teaching.course.authoring.apply_proposal']
  AND scope->'targetKinds'='["teaching_course"]'::jsonb
  ORDER BY (authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp())) DESC,created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v1',
  'carrierReady',c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active'),
  'courses',courses,
  'authorization',CASE WHEN a.id IS NULL THEN NULL ELSE jsonb_build_object('authorizationId',a.id,'courseId',a.scope->'targetIds'->>0,
   'state',CASE WHEN a.authorization_state='active' AND a.ends_at<=clock_timestamp() THEN 'expired' ELSE a.authorization_state END,
   'endsAt',a.ends_at,'credentialActive',EXISTS(SELECT 1 FROM atlas.delegated_agent_credentials cr WHERE cr.authorization_id=a.id
    AND cr.credential_state='active' AND cr.begins_at<=clock_timestamp() AND cr.expires_at=a.ends_at AND cr.expires_at>clock_timestamp()
    AND cr.metadata->>'privateCarrierCredentialV1'='true'
    AND a.authorization_state='active' AND a.begins_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active'))) END);
END $status$;

CREATE FUNCTION public.shared_private_atlas_carrier_enroll_self_api_v1(p_course_id uuid,p_ends_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $enroll$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); pr atlas.principals%ROWTYPE; c atlas.delegated_agent_carriers%ROWTYPE; a atlas.delegated_agent_authorizations%ROWTYPE; ids uuid[]; aid uuid;
 scope_value jsonb:=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(p_course_id::text));
 policy_value jsonb:='{"forceAllCommits":true}'::jsonb;
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
 SELECT array_agg(id) INTO ids FROM atlas.delegated_agent_authorizations WHERE carrier_id=c.id AND principal_id=pr.id
  AND authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp());
 IF coalesce(cardinality(ids),0)>1 THEN RAISE EXCEPTION 'multiple active delegations require review' USING ERRCODE='40001'; END IF;
 IF coalesce(cardinality(ids),0)=1 THEN
  SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=ids[1];
  IF a.ledger_id IS NOT NULL OR a.delegating_seat_id IS NOT NULL OR a.scope IS DISTINCT FROM scope_value
   OR a.confirmation_policy IS DISTINCT FROM policy_value OR a.allowed_command_keys IS DISTINCT FROM ARRAY['teaching.course.authoring.apply_proposal']
   OR a.denied_command_keys IS DISTINCT FROM ARRAY[]::text[] OR a.max_execution_class<>'commit'
   OR a.ends_at IS DISTINCT FROM p_ends_at THEN
   RAISE EXCEPTION 'revoke existing delegation before creating another' USING ERRCODE='40001'; END IF;
  aid:=a.id;
 ELSE
  aid:=atlas.establish_delegated_agent_authorization_self_api_v1(c.id,NULL,NULL,'commit',
   ARRAY['teaching.course.authoring.apply_proposal'],ARRAY[]::text[],scope_value,policy_value,
   'Owner-approved private ChatGPT Course authoring pilot',p_ends_at);
 END IF;
 IF NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(aid,'teaching.course.authoring.apply_proposal',1,
  jsonb_build_object('kind','teaching_course','id',p_course_id::text))->>'allowed')::boolean,false)
 THEN RAISE EXCEPTION 'delegation authority unavailable' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_enrollment_v1','authorizationId',aid,'courseId',p_course_id,
  'state','active','endsAt',p_ends_at,'replayed',coalesce(cardinality(ids),0)=1);
END $enroll$;

CREATE FUNCTION public.shared_private_atlas_carrier_revoke_self_api_v1(p_authorization_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $revoke$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); j jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations a JOIN atlas.principals pr ON pr.id=a.principal_id
  JOIN atlas.delegated_agent_carriers c ON c.id=a.carrier_id
  WHERE a.id=p_authorization_id AND pr.user_id=u AND c.stable_key='chatgpt_atlas_private'
   AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
   AND c.metadata->>'ownerPrincipalId'=pr.id::text
   AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL
   AND a.allowed_command_keys=ARRAY['teaching.course.authoring.apply_proposal'])
 THEN RAISE EXCEPTION 'owned private carrier delegation required' USING ERRCODE='42501'; END IF;
 j:=atlas.revoke_delegated_agent_authorization_self_api_v1(p_authorization_id,'Principal revoked private ChatGPT delegation');
 IF j->>'authorizationId' IS DISTINCT FROM p_authorization_id::text OR j->>'state' IS DISTINCT FROM 'revoked'
 THEN RAISE EXCEPTION 'unverified revocation receipt' USING ERRCODE='55000'; END IF;
 RETURN j||jsonb_build_object('contractVersion','atlas_private_carrier_revocation_v1');
END $revoke$;

REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_status_self_api_v1(),
 public.shared_private_atlas_carrier_enroll_self_api_v1(uuid,timestamptz),public.shared_private_atlas_carrier_revoke_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_status_self_api_v1(),
 public.shared_private_atlas_carrier_enroll_self_api_v1(uuid,timestamptz),public.shared_private_atlas_carrier_revoke_self_api_v1(uuid)
 TO authenticated;


-- Operator/admission boundary for this exact owner-private Sites pilot.
-- The transport bearer must be generated and delivered outside chat and source
-- control. The issuer takes ONLY its hash, never creates or returns a bearer.
-- Active signed grant, explicit Course scope and current source authority are
-- independently verified. This helper is internal and does not mutate data.
CREATE FUNCTION atlas.private_atlas_carrier_grant_current_v1(p_authorization_id uuid)
RETURNS boolean LANGUAGE sql VOLATILE SET search_path TO pg_catalog AS $grant_check$
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
   AND a.purpose='Owner-approved private ChatGPT Course authoring pilot'
   AND a.authorization_state='active' AND a.begins_at<=clock_timestamp()
   AND a.ends_at IS NOT NULL AND isfinite(a.ends_at) AND a.ends_at>clock_timestamp()
   AND a.ends_at<=a.begins_at+interval '24 hours'
   AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL AND a.max_execution_class='commit'
   AND a.allowed_command_keys=ARRAY['teaching.course.authoring.apply_proposal']
   AND a.denied_command_keys=ARRAY[]::text[]
   AND a.scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(tc.id::text))
   AND a.confirmation_policy='{"forceAllCommits":true}'::jsonb
   AND titus.authoring_grant_current_active_v1(e.id)
   AND coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,'teaching.course.authoring.apply_proposal',1,
    jsonb_build_object('kind','teaching_course','id',tc.id::text))->>'allowed')::boolean,false)
   AND NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations x WHERE x.id<>a.id AND x.carrier_id=a.carrier_id
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp()))
 );
$grant_check$;
REVOKE ALL ON FUNCTION atlas.private_atlas_carrier_grant_current_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.issue_private_atlas_carrier_credential_v1(p_authorization_id uuid,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $issue$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE; c atlas.delegated_agent_credentials%ROWTYPE; cid uuid;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'canonical credential hash required' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=p_authorization_id FOR UPDATE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_grant_current_v1(p_authorization_id) THEN
  RAISE EXCEPTION 'current exact private carrier grant required' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF FOUND THEN
  IF c.authorization_id<>a.id OR c.credential_state<>'active'
   OR c.expires_at IS DISTINCT FROM a.ends_at OR c.begins_at>clock_timestamp()
   OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'credential identity mismatch' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','atlas_private_carrier_credential_v1','authorizationId',a.id,
   'credentialId',c.id,'expiresAt',c.expires_at,'replayed',true);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.delegated_agent_credentials WHERE authorization_id=a.id AND credential_state='active'
   AND (expires_at IS NULL OR expires_at>clock_timestamp())) THEN
  RAISE EXCEPTION 'revoke existing private grant before reissuing' USING ERRCODE='40001'; END IF;
 cid:=atlas.issue_delegated_agent_credential_service_v1(a.id,p_token_hash,a.ends_at,'{"privateCarrierCredentialV1":true}'::jsonb);
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_credential_v1','authorizationId',a.id,
  'credentialId',cid,'expiresAt',a.ends_at,'replayed',false);
END $issue$;

-- Per-credential fixed-minute rate admission, serialized on the existing
-- credential row. No new authority table or process-local counter. No token
-- data is returned. This runs in its own RPC transaction before dispatch;
-- therefore failed/malformed downstream commands cannot undo admission.
CREATE FUNCTION atlas.admit_private_atlas_carrier_command_v1(p_token_hash text)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $admit$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE; c atlas.delegated_agent_credentials%ROWTYPE;
 aid uuid; window_id bigint; used int; previous jsonb;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF aid IS NULL THEN RETURN false; END IF;
 -- Same authorization-before-credential order as the canonical executor.
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_grant_current_v1(aid) THEN RETURN false; END IF;
 SELECT * INTO c FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
 IF NOT FOUND OR c.credential_state<>'active' OR c.begins_at>clock_timestamp()
  OR c.expires_at IS DISTINCT FROM a.ends_at OR c.expires_at<=clock_timestamp()
  OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true' THEN RETURN false; END IF;
 IF NOT atlas.private_atlas_carrier_grant_current_v1(aid) THEN RETURN false; END IF;
 window_id:=floor(extract(epoch FROM clock_timestamp())/60)::bigint;
 previous:=c.metadata->'privateCarrierAdmissionV1';
 used:=0;
 IF previous IS NOT NULL THEN
  IF jsonb_typeof(previous)<>'object' OR coalesce(previous->>'window','') !~ '^[0-9]{1,18}$'
   OR coalesce(previous->>'count','') !~ '^[0-9]{1,2}$' THEN RETURN false; END IF;
  IF (previous->>'window')::bigint>window_id THEN RETURN false; END IF;
  IF (previous->>'window')::bigint=window_id THEN used:=(previous->>'count')::int; END IF;
 END IF;
 IF used>=12 THEN RETURN false; END IF;
 UPDATE atlas.delegated_agent_credentials SET metadata=jsonb_set(metadata,'{privateCarrierAdmissionV1}',
  jsonb_build_object('window',window_id,'count',used+1),true) WHERE id=c.id;
 RETURN true;
END $admit$;

REVOKE ALL ON FUNCTION atlas.issue_private_atlas_carrier_credential_v1(uuid,text),
 atlas.admit_private_atlas_carrier_command_v1(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.issue_private_atlas_carrier_credential_v1(uuid,text),
 atlas.admit_private_atlas_carrier_command_v1(text) TO service_role;

CREATE FUNCTION public.shared_private_atlas_carrier_issue_service_v1(p_authorization_id uuid,p_token_hash text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog AS $issue_api$
 SELECT atlas.issue_private_atlas_carrier_credential_v1(p_authorization_id,p_token_hash);
$issue_api$;
CREATE FUNCTION public.shared_private_atlas_carrier_admit_service_v1(p_token_hash text)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog AS $admit_api$
 SELECT atlas.admit_private_atlas_carrier_command_v1(p_token_hash);
$admit_api$;
REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_issue_service_v1(uuid,text),
 public.shared_private_atlas_carrier_admit_service_v1(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_issue_service_v1(uuid,text),
 public.shared_private_atlas_carrier_admit_service_v1(text) TO service_role;

COMMIT;
