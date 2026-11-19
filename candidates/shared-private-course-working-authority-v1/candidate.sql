-- Held source only. No new Course, grant, credential, or live migration.
-- One original; working save is not publication. Do not fabricate confirmation.
BEGIN;

INSERT INTO atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,
 confirmation_requirement,handler_key,status,input_contract,target_contract)
 VALUES('teaching.course.authoring.save_draft',1,'Save private Course working draft','personal','commit',
 'none','teaching.course.authoring.save_draft.v1','active',
 '{"contractVersion":"titus_course_authoring_proposal_v1","maxItems":12}'::jsonb,'{"kind":"teaching_course"}'::jsonb);

CREATE FUNCTION atlas.private_atlas_carrier_working_grant_current_v1(p_authorization_id uuid)
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
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp()))
 );
$grant_check$;

CREATE FUNCTION atlas.private_atlas_carrier_any_grant_current_v2(p_authorization_id uuid)
RETURNS boolean LANGUAGE sql VOLATILE SET search_path TO pg_catalog AS $any$
 SELECT atlas.private_atlas_carrier_grant_current_v1(p_authorization_id)
  OR atlas.private_atlas_carrier_working_grant_current_v1(p_authorization_id);
$any$;
REVOKE ALL ON FUNCTION atlas.private_atlas_carrier_working_grant_current_v1(uuid),
 atlas.private_atlas_carrier_any_grant_current_v2(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_private_atlas_carrier_enroll_working_self_api_v1(p_course_id uuid,p_ends_at timestamptz)
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
  AND authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp());
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

CREATE FUNCTION public.shared_private_atlas_carrier_status_self_api_v2()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $status$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); c atlas.delegated_agent_carriers%ROWTYPE; a atlas.delegated_agent_authorizations%ROWTYPE; pid uuid; courses jsonb:='[]'; person uuid;
BEGIN
 SELECT id INTO pid FROM atlas.principals WHERE user_id=u;
 IF pid IS NULL THEN RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v2','carrierReady',false,'courses',courses,'authorization',NULL); END IF;
 SELECT * INTO c FROM atlas.delegated_agent_carriers WHERE stable_key='chatgpt_atlas_private'
  AND provider_key='openai' AND carrier_kind='ai_agent'
  AND metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
  AND metadata->>'ownerPrincipalId'=pid::text;
 IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v2','carrierReady',false,'courses',courses,'authorization',NULL); END IF;
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
  AND ledger_id IS NULL AND delegating_seat_id IS NULL AND allowed_command_keys IN (ARRAY['teaching.course.authoring.apply_proposal'],ARRAY['teaching.course.authoring.save_draft'])
  AND scope->'targetKinds'='["teaching_course"]'::jsonb
  ORDER BY (authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp())) DESC,created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('contractVersion','atlas_private_carrier_status_v2',
  'carrierReady',c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active'),
  'courses',courses,
  'authorization',CASE WHEN a.id IS NULL THEN NULL ELSE jsonb_build_object('authorizationId',a.id,'courseId',a.scope->'targetIds'->>0,
   'mode',CASE WHEN a.allowed_command_keys=ARRAY['teaching.course.authoring.save_draft'] THEN 'working_draft' ELSE 'review_required' END,
   'state',CASE WHEN a.authorization_state='active' AND a.ends_at<=clock_timestamp() THEN 'expired' ELSE a.authorization_state END,
   'endsAt',a.ends_at,'credentialActive',atlas.private_atlas_carrier_any_grant_current_v2(a.id) AND EXISTS(SELECT 1 FROM atlas.delegated_agent_credentials cr WHERE cr.authorization_id=a.id
    AND cr.credential_state='active' AND cr.begins_at<=clock_timestamp() AND cr.expires_at=a.ends_at AND cr.expires_at>clock_timestamp()
    AND cr.metadata->>'privateCarrierCredentialV1'='true'
    AND a.authorization_state='active' AND a.begins_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active'))) END);
END $status$;

CREATE FUNCTION public.shared_private_atlas_carrier_revoke_self_api_v2(p_authorization_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $revoke$
DECLARE u uuid:=atlas.require_private_carrier_signed_user_v1(); j jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations a JOIN atlas.principals pr ON pr.id=a.principal_id
  JOIN atlas.delegated_agent_carriers c ON c.id=a.carrier_id
  WHERE a.id=p_authorization_id AND pr.user_id=u AND c.stable_key='chatgpt_atlas_private'
   AND c.metadata->>'pluginId'='plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1'
   AND c.metadata->>'ownerPrincipalId'=pr.id::text
   AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL
   AND a.allowed_command_keys IN (ARRAY['teaching.course.authoring.apply_proposal'],ARRAY['teaching.course.authoring.save_draft']))
 THEN RAISE EXCEPTION 'owned private carrier delegation required' USING ERRCODE='42501'; END IF;
 j:=atlas.revoke_delegated_agent_authorization_self_api_v1(p_authorization_id,'Principal revoked private ChatGPT delegation');
 IF j->>'authorizationId' IS DISTINCT FROM p_authorization_id::text OR j->>'state' IS DISTINCT FROM 'revoked'
 THEN RAISE EXCEPTION 'unverified revocation receipt' USING ERRCODE='55000'; END IF;
 RETURN j||jsonb_build_object('contractVersion','atlas_private_carrier_revocation_v2');
END $revoke$;

REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_enroll_working_self_api_v1(uuid,timestamptz),
 public.shared_private_atlas_carrier_status_self_api_v2(),public.shared_private_atlas_carrier_revoke_self_api_v2(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_enroll_working_self_api_v1(uuid,timestamptz),
 public.shared_private_atlas_carrier_status_self_api_v2(),public.shared_private_atlas_carrier_revoke_self_api_v2(uuid)
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.issue_private_atlas_carrier_credential_v1(p_authorization_id uuid,p_token_hash text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $issue$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE; c atlas.delegated_agent_credentials%ROWTYPE; cid uuid;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'canonical credential hash required' USING ERRCODE='22023'; END IF;
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=p_authorization_id FOR UPDATE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_any_grant_current_v2(p_authorization_id) THEN
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

CREATE OR REPLACE FUNCTION atlas.admit_private_atlas_carrier_command_v1(p_token_hash text)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $admit$
DECLARE a atlas.delegated_agent_authorizations%ROWTYPE; c atlas.delegated_agent_credentials%ROWTYPE;
 aid uuid; window_id bigint; used int; previous jsonb;
BEGIN
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF aid IS NULL THEN RETURN false; END IF;
 -- Same authorization-before-credential order as the canonical executor.
 SELECT * INTO a FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_any_grant_current_v2(aid) THEN RETURN false; END IF;
 SELECT * INTO c FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
 IF NOT FOUND OR c.credential_state<>'active' OR c.begins_at>clock_timestamp()
  OR c.expires_at IS DISTINCT FROM a.ends_at OR c.expires_at<=clock_timestamp()
  OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true' THEN RETURN false; END IF;
 IF NOT atlas.private_atlas_carrier_any_grant_current_v2(aid) THEN RETURN false; END IF;
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

CREATE OR REPLACE FUNCTION atlas.course_authoring_receipt_v1(p_invocation uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $receipt$
DECLARE v atlas.agent_command_invocations%ROWTYPE;i jsonb;u uuid;r uuid;n int;expected int;
 results jsonb:='[]';cid uuid;expected_appends int;
BEGIN
 SELECT * INTO STRICT v FROM atlas.agent_command_invocations WHERE id=p_invocation;
 IF v.command_key NOT IN ('teaching.course.authoring.apply_proposal','teaching.course.authoring.save_draft') OR v.command_version<>1 THEN
  RAISE EXCEPTION 'wrong command receipt' USING ERRCODE='22023'; END IF;
 cid:=(v.target->>'id')::uuid;
 PERFORM atlas.validate_course_authoring_proposal_v1(v.input,cid);
 SELECT count(*) INTO expected_appends FROM jsonb_array_elements(v.input->'items') i0 WHERE i0->>'operation'='append_unit';
 IF (SELECT count(*) FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id=v.id)
   <>jsonb_array_length(v.input->'items') OR
  (SELECT count(*) FROM atlas.teaching_course_units WHERE created_by_agent_invocation_id=v.id)<>expected_appends THEN
  RAISE EXCEPTION 'incomplete Course receipt' USING ERRCODE='55000'; END IF;
 FOR i IN SELECT value FROM jsonb_array_elements(v.input->'items') LOOP
  expected:=CASE WHEN i->>'operation'='append_unit' THEN 0 ELSE (i->>'expectedRevision')::int END;
  SELECT un.unit_id,rr.revision_id,rr.revision_number INTO STRICT u,r,n
   FROM atlas.teaching_course_unit_revisions rr JOIN atlas.teaching_course_units un ON un.unit_id=rr.unit_id
   WHERE rr.recorded_by_agent_invocation_id=v.id AND rr.edit_request_id=(i->>'requestId')::uuid
    AND un.course_id=cid AND rr.body_text=i->>'text' AND rr.based_on_revision=expected
    AND rr.recorded_by_auth_user_id=CASE WHEN v.command_key='teaching.course.authoring.save_draft'
     THEN (SELECT created_by_user_id FROM atlas.delegated_agent_authorizations WHERE id=v.authorization_id AND principal_id=v.principal_id)
     ELSE v.confirmed_by_user_id END
    AND rr.recorded_by_person_entity_id=(SELECT created_by_person_entity_id FROM atlas.teaching_courses WHERE id=cid)
    AND rr.revision_number=expected+1 AND
    ((i->>'operation'='append_unit' AND un.created_by_agent_invocation_id=v.id AND un.create_request_id=(i->>'requestId')::uuid)
      OR (i->>'operation'='revise_unit' AND un.unit_id=(i->>'unitId')::uuid));
  results:=results||jsonb_build_array(jsonb_build_object('requestId',i->>'requestId','operation',i->>'operation',
   'unitId',u,'revisionId',r,'revisionNumber',n));
 END LOOP;
 RETURN jsonb_build_object('contractVersion','shared_course_authoring_applied_v1','courseId',cid,
  'proposalId',v.input->>'proposalId','invocationId',v.id,'items',results);
END $receipt$;

CREATE OR REPLACE FUNCTION atlas.guard_course_authoring_invocation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $guard$
BEGIN
 IF OLD.command_key IN ('teaching.course.authoring.apply_proposal','teaching.course.authoring.save_draft') THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Course invocation history is immutable' USING ERRCODE='55000'; END IF;
  IF ROW(OLD.id,OLD.authorization_id,OLD.credential_id,OLD.carrier_id,OLD.principal_id,OLD.ledger_id,
    OLD.delegating_seat_id,OLD.command_key,OLD.command_version,OLD.idempotency_key,OLD.target,OLD.input,OLD.confirmation_required)
   IS DISTINCT FROM ROW(NEW.id,NEW.authorization_id,NEW.credential_id,NEW.carrier_id,NEW.principal_id,NEW.ledger_id,
    NEW.delegating_seat_id,NEW.command_key,NEW.command_version,NEW.idempotency_key,NEW.target,NEW.input,NEW.confirmation_required)
   OR (OLD.confirmed_at IS NOT NULL AND
       ROW(OLD.confirmed_at,OLD.confirmed_by_user_id) IS DISTINCT FROM ROW(NEW.confirmed_at,NEW.confirmed_by_user_id))
   OR (OLD.invocation_state IN ('succeeded','failed','cancelled','rejected') AND OLD IS DISTINCT FROM NEW) THEN
   RAISE EXCEPTION 'Course invocation identity or final receipt is immutable' USING ERRCODE='55000'; END IF;
  IF OLD.command_key='teaching.course.authoring.save_draft' AND
   (NEW.confirmation_required OR NEW.confirmed_at IS NOT NULL OR NEW.confirmed_by_user_id IS NOT NULL) THEN
   RAISE EXCEPTION 'working draft must not manufacture principal confirmation' USING ERRCODE='55000'; END IF;
  IF NEW.invocation_state='succeeded' AND OLD.invocation_state<>'succeeded' THEN
   IF OLD.invocation_state<>'executing' OR (OLD.command_key='teaching.course.authoring.apply_proposal' AND NEW.confirmed_at IS NULL) OR
    NEW.result IS DISTINCT FROM atlas.course_authoring_receipt_v1(OLD.id) THEN
    RAISE EXCEPTION 'Course success requires source receipt' USING ERRCODE='55000'; END IF;
  END IF;
 ELSIF TG_OP='UPDATE' AND NEW.command_key IN ('teaching.course.authoring.apply_proposal','teaching.course.authoring.save_draft') THEN
  RAISE EXCEPTION 'cannot reclassify an invocation' USING ERRCODE='55000';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $guard$;

CREATE FUNCTION atlas.execute_private_course_authoring_v2(p_token_hash text,p_invocation uuid,p_proposal jsonb,p_command text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $apply$
DECLARE v atlas.agent_command_invocations%ROWTYPE;a atlas.delegated_agent_authorizations%ROWTYPE;
 c atlas.delegated_agent_credentials%ROWTYPE;pr atlas.principals%ROWTYPE;
 cid uuid;person uuid;u uuid;req uuid;i jsonb;j jsonb;latest int;expected int;pos int;
 n int;new_count int;binding_ids uuid[];
BEGIN
 SELECT * INTO v FROM atlas.agent_command_invocations WHERE id=p_invocation FOR UPDATE;
 IF NOT FOUND OR p_command IS NULL OR p_command NOT IN ('teaching.course.authoring.apply_proposal','teaching.course.authoring.save_draft') OR v.command_key<>p_command OR v.command_version<>1
  OR v.input IS DISTINCT FROM p_proposal OR v.target IS NULL THEN
  RAISE EXCEPTION 'exact invocation required' USING ERRCODE='42501'; END IF;
 cid:=(v.target->>'id')::uuid;
 IF v.target IS DISTINCT FROM jsonb_build_object('kind','teaching_course','id',cid::text)
  OR v.idempotency_key IS DISTINCT FROM lower(p_proposal->>'proposalId') THEN
  RAISE EXCEPTION 'exact Course target required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.validate_course_authoring_proposal_v1(p_proposal,cid);
 SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=v.authorization_id FOR SHARE;
 SELECT * INTO STRICT c FROM atlas.delegated_agent_credentials WHERE id=v.credential_id FOR SHARE;
 SELECT * INTO STRICT pr FROM atlas.principals WHERE id=v.principal_id FOR SHARE;
 PERFORM 1 FROM atlas.delegated_agent_carriers WHERE id=v.carrier_id AND status='active' FOR SHARE;
 IF NOT FOUND OR c.token_hash IS DISTINCT FROM lower(p_token_hash) OR c.authorization_id<>a.id
  OR a.carrier_id<>v.carrier_id OR a.principal_id<>pr.id OR a.ledger_id IS NOT NULL OR v.ledger_id IS NOT NULL
  OR a.delegating_seat_id IS NOT NULL OR v.delegating_seat_id IS NOT NULL
  OR a.authorization_state<>'active' OR a.begins_at>clock_timestamp()
  OR (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp()) OR c.credential_state<>'active'
  OR c.begins_at>clock_timestamp() OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR pr.status<>'active'
  OR (p_command='teaching.course.authoring.apply_proposal' AND (NOT v.confirmation_required
      OR v.confirmed_at IS NULL OR v.confirmed_by_user_id IS DISTINCT FROM pr.user_id))
  OR (p_command='teaching.course.authoring.save_draft' AND (v.confirmation_required
      OR v.confirmed_at IS NOT NULL OR v.confirmed_by_user_id IS NOT NULL
      OR a.created_by_user_id IS DISTINCT FROM pr.user_id
      OR c.expires_at IS DISTINCT FROM a.ends_at
      OR c.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
      OR NOT atlas.private_atlas_carrier_working_grant_current_v1(a.id)))
  OR NOT (v.command_key=ANY(a.allowed_command_keys)) OR v.command_key=ANY(a.denied_command_keys)
  OR a.scope->'targetIds' IS DISTINCT FROM jsonb_build_array(cid::text)
  OR a.scope->'targetKinds' IS DISTINCT FROM jsonb_build_array('teaching_course')
  OR NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,v.command_key,1,v.target)->>'allowed')::boolean,false) THEN
  RAISE EXCEPTION 'current confirmed and exact scoped delegation required' USING ERRCODE='42501'; END IF;
 -- Resolve from the authenticated principal's canonical source binding.
 SELECT array_agg(b.person_entity_id) INTO binding_ids FROM (
  SELECT person_entity_id FROM reality.auth_person_bindings
  WHERE auth_user_id=pr.user_id AND binding_state='active' AND retired_at IS NULL FOR SHARE
 ) b;
 IF coalesce(cardinality(binding_ids),0)<>1 THEN
  RAISE EXCEPTION 'unique current Person binding required' USING ERRCODE='42501'; END IF;
 person:=binding_ids[1];
 PERFORM 1 FROM reality.entities WHERE id=person AND entity_kind='person' AND identity_state='canonical' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'canonical Person required' USING ERRCODE='42501'; END IF;
 -- Lock the grant or founding-owner relation which the released product gate reads.
 PERFORM 1 FROM titus.course_authoring_access_grants WHERE person_entity_id=person FOR SHARE;
 PERFORM 1 FROM reality.responsibility_relations WHERE carrier_person_entity_id=person
  AND responsibility_key='titus_private_pilot_issuance' AND jurisdiction_kind='domain'
  AND jurisdiction_domain='titus' FOR SHARE;
 IF NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'current Titus access required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.teaching_courses WHERE id=cid AND created_by_person_entity_id=person
  AND status='active' AND ledger_id IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active original Course required' USING ERRCODE='42501'; END IF;
 IF p_command='teaching.course.authoring.save_draft' AND NOT atlas.private_atlas_carrier_working_grant_current_v1(a.id)
 THEN RAISE EXCEPTION 'working draft authority unavailable' USING ERRCODE='42501'; END IF;
 -- Wall-clock validity can change while awaiting the Course lock.
 IF (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp())
  OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'delegation expired before Course write' USING ERRCODE='42501'; END IF;
 IF v.invocation_state='succeeded' THEN
  j:=atlas.course_authoring_receipt_v1(v.id);
  IF v.result IS DISTINCT FROM j THEN RAISE EXCEPTION 'unverified completion' USING ERRCODE='55000'; END IF;
  RETURN j;
 END IF;
 IF v.invocation_state<>'authorized' THEN RAISE EXCEPTION 'confirmed unexecuted invocation required' USING ERRCODE='42501'; END IF;
 SELECT count(*),coalesce(max(display_position),0) INTO n,pos FROM atlas.teaching_course_units WHERE course_id=cid;
 SELECT count(*) INTO new_count FROM jsonb_array_elements(p_proposal->'items') el WHERE el->>'operation'='append_unit';
 IF n+new_count>100 THEN RAISE EXCEPTION 'Course Unit limit' USING ERRCODE='22023'; END IF;
 PERFORM atlas.mark_delegated_agent_command_executing_service_v1(v.id);
 FOR i IN SELECT value FROM jsonb_array_elements(p_proposal->'items') LOOP
  req:=(i->>'requestId')::uuid;
  IF EXISTS(SELECT 1 FROM atlas.teaching_course_units WHERE course_id=cid AND create_request_id=req)
   OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions rr JOIN atlas.teaching_course_units un ON un.unit_id=rr.unit_id
       WHERE un.course_id=cid AND rr.edit_request_id=req) THEN
   RAISE EXCEPTION 'request already used by another write' USING ERRCODE='23505'; END IF;
  IF i->>'operation'='append_unit' THEN
   pos:=pos+1024;expected:=0;
   INSERT INTO atlas.teaching_course_units(course_id,create_request_id,kind,title,display_position,
     created_by_person_entity_id,created_by_auth_user_id,created_by_agent_invocation_id)
    VALUES(cid,req,i->>'kind',i->>'title',pos,person,pr.user_id,v.id) RETURNING unit_id INTO u;
  ELSE
   u:=(i->>'unitId')::uuid;expected:=(i->>'expectedRevision')::integer;
   PERFORM 1 FROM atlas.teaching_course_units WHERE unit_id=u AND course_id=cid AND kind=i->>'kind' AND title=i->>'title';
   IF NOT FOUND THEN RAISE EXCEPTION 'exact Unit required' USING ERRCODE='42501'; END IF;
  END IF;
  SELECT coalesce(max(revision_number),0) INTO latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=u;
  IF latest<>expected THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,
    recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_by_agent_invocation_id)
   VALUES(u,req,expected,expected+1,i->>'text',person,pr.user_id,v.id);
 END LOOP;
 IF (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp())
  OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'delegation expired during Course write' USING ERRCODE='42501'; END IF;
 IF p_command='teaching.course.authoring.save_draft' AND NOT atlas.private_atlas_carrier_working_grant_current_v1(a.id)
 THEN RAISE EXCEPTION 'working draft authority ended during save' USING ERRCODE='42501'; END IF;
 j:=atlas.course_authoring_receipt_v1(v.id);
 PERFORM atlas.complete_delegated_agent_command_service_v1(v.id,true,j,'{}'::jsonb);
 RETURN j;
END $apply$;

REVOKE ALL ON FUNCTION atlas.execute_private_course_authoring_v2(text,uuid,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION atlas.apply_course_authoring_proposal_service_v1(p_token_hash text,p_invocation uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $reviewed$
 SELECT atlas.execute_private_course_authoring_v2(p_token_hash,p_invocation,p_proposal,'teaching.course.authoring.apply_proposal');
$reviewed$;
CREATE FUNCTION atlas.save_private_course_draft_service_v1(p_token_hash text,p_course uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $save$
DECLARE aid uuid; cred atlas.delegated_agent_credentials%ROWTYPE; j jsonb; inv uuid;
BEGIN
 PERFORM atlas.validate_course_authoring_proposal_v1(p_proposal,p_course);
 IF p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'working credential required' USING ERRCODE='42501'; END IF;
 SELECT authorization_id INTO aid FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash;
 IF NOT FOUND THEN RAISE EXCEPTION 'working credential required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.delegated_agent_authorizations WHERE id=aid FOR SHARE;
 IF NOT FOUND OR NOT atlas.private_atlas_carrier_working_grant_current_v1(aid)
   OR NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations WHERE id=aid
    AND scope=jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(p_course::text)))
 THEN RAISE EXCEPTION 'exact working draft grant required' USING ERRCODE='42501'; END IF;
 SELECT * INTO cred FROM atlas.delegated_agent_credentials WHERE token_hash=p_token_hash AND authorization_id=aid FOR UPDATE;
 IF NOT FOUND OR cred.credential_state<>'active' OR cred.begins_at>clock_timestamp()
   OR cred.expires_at IS NULL OR cred.expires_at<=clock_timestamp()
   OR cred.expires_at IS DISTINCT FROM (SELECT ends_at FROM atlas.delegated_agent_authorizations WHERE id=aid)
   OR cred.metadata->>'privateCarrierCredentialV1' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'current issued working credential required' USING ERRCODE='42501'; END IF;
 j:=atlas.begin_delegated_agent_command_service_v1(p_token_hash,'teaching.course.authoring.save_draft',1,
  jsonb_build_object('kind','teaching_course','id',p_course::text),p_proposal,lower(p_proposal->>'proposalId'));
 inv:=(j->>'invocationId')::uuid;
 IF inv IS NULL OR j->>'state' NOT IN ('authorized','succeeded')
   OR j->'confirmationRequired' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'working invocation unavailable' USING ERRCODE='42501'; END IF;
 RETURN atlas.execute_private_course_authoring_v2(p_token_hash,inv,p_proposal,'teaching.course.authoring.save_draft');
END $save$;
REVOKE ALL ON FUNCTION atlas.save_private_course_draft_service_v1(text,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.save_private_course_draft_service_v1(text,uuid,jsonb) TO service_role;
CREATE FUNCTION public.shared_delegated_course_save_draft_service_v1(p_token_hash text,p_course uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO pg_catalog AS $api$
 SELECT atlas.save_private_course_draft_service_v1(p_token_hash,p_course,p_proposal);
$api$;
REVOKE ALL ON FUNCTION public.shared_delegated_course_save_draft_service_v1(text,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_delegated_course_save_draft_service_v1(text,uuid,jsonb) TO service_role;


COMMIT;
