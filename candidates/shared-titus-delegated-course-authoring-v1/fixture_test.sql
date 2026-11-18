-- Fictional-only fixture, run in the existing isolated Titus GoTrue/PG harness.
-- The caller supplies the fictional issuer/outsider auth UUIDs and session UUIDs
-- as local custom GUCs. Never run this on a production database.
BEGIN;
DO $setup$
DECLARE owner_auth uuid:=current_setting('test.course_agent_owner')::uuid;
 outsider_auth uuid:=current_setting('test.course_agent_outsider')::uuid;
 person uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 pid uuid:=gen_random_uuid();carrier uuid:=gen_random_uuid();az uuid:=gen_random_uuid();cred uuid:=gen_random_uuid();
 cid uuid:='11111111-1111-4111-8111-111111111111';
 unit uuid:='31111111-1111-4111-8111-111111111111';
 j jsonb;packet jsonb;stale jsonb;inv uuid;stale_inv uuid;other jsonb;
 key text:=repeat('a',64);
 b jsonb:=jsonb_build_array(jsonb_build_object('reference','fictional-local-source','description','Only a test reference'));
BEGIN
 -- Existing minimal fixture has a stub atlas.people/principals schema.
 -- A deliberately unrelated legacy person ID must not become the canonical Person.
 INSERT INTO atlas.people(id) VALUES(gen_random_uuid()) RETURNING id INTO unit;
 INSERT INTO atlas.principals(id,user_id,status,person_id) VALUES(pid,owner_auth,'active',unit);
 INSERT INTO atlas.principals(id,user_id,status) VALUES(gen_random_uuid(),outsider_auth,'active');
 unit:='31111111-1111-4111-8111-111111111111';
 INSERT INTO atlas.delegated_agent_carriers(id,stable_key,display_name,carrier_kind)
 VALUES(carrier,'fictional_course_agent','Fictional course test','ai_agent');
 INSERT INTO atlas.delegated_agent_authorizations(id,carrier_id,principal_id,max_execution_class,allowed_command_keys,scope,purpose)
 VALUES(az,carrier,pid,'commit',ARRAY['teaching.course.authoring.apply_proposal'],
  jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array(cid::text)),'Fictional test only');
 INSERT INTO atlas.delegated_agent_credentials(id,authorization_id,token_hash) VALUES(cred,az,key);
 packet:=jsonb_build_object('contractVersion','titus_course_authoring_proposal_v1','courseId',cid,'proposalId',gen_random_uuid(),
  'items',jsonb_build_array(
   jsonb_build_object('operation','append_unit','requestId',gen_random_uuid(),'kind','assignment','title','Fictional new homework','text','Fictional homework draft','basis',b),
   jsonb_build_object('operation','revise_unit','requestId',gen_random_uuid(),'kind','lesson','title','Class 1','unitId',unit,'expectedRevision',2,'text','Fictional approved revision','basis',b)));
 stale:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(packet,'{proposalId}',to_jsonb(gen_random_uuid())),
  '{items,0,requestId}',to_jsonb(gen_random_uuid())),'{items,1,requestId}',to_jsonb(gen_random_uuid())),'{items,1,expectedRevision}','1'::jsonb);
 j:=atlas.prepare_course_authoring_proposal_service_v1(key,cid,packet);
 inv:=(j->>'invocationId')::uuid;
 IF j->>'state'<>'needs_confirmation' OR j->>'confirmationRequired'<>'true' THEN RAISE EXCEPTION 'explicit confirmation missing';END IF;
 IF atlas.prepare_course_authoring_proposal_service_v1(key,cid,packet)->>'invocationId'<>inv::text THEN RAISE EXCEPTION 'prepare replay changed';END IF;
 BEGIN PERFORM atlas.prepare_course_authoring_proposal_service_v1(key,cid,jsonb_set(packet,'{items,0,text}','"changed"'::jsonb));
  RAISE EXCEPTION 'changed replay accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
  RAISE EXCEPTION 'unconfirmed write allowed' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 other:=jsonb_set(packet,'{courseId}',to_jsonb(gen_random_uuid()));
 BEGIN PERFORM atlas.prepare_course_authoring_proposal_service_v1(key,(other->>'courseId')::uuid,other);
  RAISE EXCEPTION 'foreign target accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM atlas.validate_course_authoring_proposal_v1(jsonb_set(packet,'{items,1,requestId}',packet#>'{items,0,requestId}'),cid);
  RAISE EXCEPTION 'duplicate request accepted' USING ERRCODE='XX000';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 j:=atlas.prepare_course_authoring_proposal_service_v1(key,cid,stale);
 stale_inv:=(j->>'invocationId')::uuid;
 PERFORM set_config('test.agent_packet',packet::text,true);
 PERFORM set_config('test.agent_invocation',inv::text,true);
 PERFORM set_config('test.agent_stale',stale::text,true);
 PERFORM set_config('test.agent_stale_invocation',stale_inv::text,true);
 PERFORM set_config('test.agent_authorization',az::text,true);
 PERFORM set_config('test.agent_credential',cred::text,true);
END $setup$;
-- Use the signed self confirmation function in an isolated role/claims context.
-- This tests the actual kernel function; not a new OAuth transport.
SELECT set_config('request.jwt.claims',current_setting('test.course_agent_outsider_claims'),true);
SET LOCAL ROLE authenticated;
DO $outsider$
BEGIN
 BEGIN PERFORM atlas.confirm_delegated_agent_command_self_api_v1(current_setting('test.agent_invocation')::uuid);
  RAISE EXCEPTION 'outsider confirmed proposal' USING ERRCODE='XX000'; EXCEPTION WHEN raise_exception THEN NULL;END;
END $outsider$;
RESET ROLE;
SELECT set_config('request.jwt.claims',current_setting('test.course_agent_owner_claims'),true);
SET LOCAL ROLE authenticated;
DO $confirm$
BEGIN
 IF atlas.confirm_delegated_agent_command_self_api_v1(current_setting('test.agent_invocation')::uuid)->>'state'<>'authorized'
  OR atlas.confirm_delegated_agent_command_self_api_v1(current_setting('test.agent_stale_invocation')::uuid)->>'state'<>'authorized'
 THEN RAISE EXCEPTION 'confirmation failed';END IF;
END $confirm$;
RESET ROLE;

DO $proof$
DECLARE inv uuid:=current_setting('test.agent_invocation')::uuid;
 stale_inv uuid:=current_setting('test.agent_stale_invocation')::uuid;
 az uuid:=current_setting('test.agent_authorization')::uuid;cred uuid:=current_setting('test.agent_credential')::uuid;
 packet jsonb:=current_setting('test.agent_packet')::jsonb;stale jsonb:=current_setting('test.agent_stale')::jsonb;
 key text:=repeat('a',64); j jsonb;uid uuid;
 cid uuid:='11111111-1111-4111-8111-111111111111';
 old_unit uuid:='31111111-1111-4111-8111-111111111111';
 before_count int;before_revision_count int;revocation_scope jsonb;
BEGIN
 SELECT count(*) INTO before_count FROM atlas.teaching_course_units WHERE course_id=cid;
 SELECT count(*) INTO before_revision_count FROM atlas.teaching_course_unit_revisions WHERE unit_id=old_unit;
 BEGIN
  PERFORM atlas.apply_course_authoring_proposal_service_v1(key,stale_inv,stale);
  RAISE EXCEPTION 'stale batch accepted' USING ERRCODE='XX000';
 EXCEPTION WHEN serialization_failure THEN NULL;END;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_units WHERE created_by_agent_invocation_id=stale_inv)
  OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id=stale_inv)
  OR (SELECT invocation_state FROM atlas.agent_command_invocations WHERE id=stale_inv)<>'authorized'
  OR EXISTS(SELECT 1 FROM atlas.agent_command_invocation_events WHERE invocation_id=stale_inv AND event_kind='execution_started')
 THEN RAISE EXCEPTION 'partial stale batch survived';END IF;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(repeat('b',64),inv,packet);
  RAISE EXCEPTION 'wrong credential accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,jsonb_set(packet,'{items,0,text}','"changed"'::jsonb));
  RAISE EXCEPTION 'changed apply accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN UPDATE atlas.agent_command_invocations SET input=jsonb_set(input,'{items,0,text}','"changed"'::jsonb) WHERE id=inv;
  RAISE EXCEPTION 'confirmed packet mutable' USING ERRCODE='XX000'; EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 BEGIN
  PERFORM atlas.mark_delegated_agent_command_executing_service_v1(inv);
  PERFORM atlas.complete_delegated_agent_command_service_v1(inv,true,'{}'::jsonb,'{}'::jsonb);
  RAISE EXCEPTION 'fabricated success accepted' USING ERRCODE='XX000';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 UPDATE atlas.delegated_agent_credentials SET credential_state='revoked' WHERE id=cred;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
  RAISE EXCEPTION 'revoked credential accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE atlas.delegated_agent_credentials SET credential_state='active' WHERE id=cred;
 UPDATE atlas.delegated_agent_authorizations SET authorization_state='revoked' WHERE id=az;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
  RAISE EXCEPTION 'revoked authorization accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE atlas.delegated_agent_authorizations SET authorization_state='active' WHERE id=az;
 UPDATE atlas.delegated_agent_authorizations SET ends_at=clock_timestamp()+interval '1 millisecond' WHERE id=az;
 PERFORM pg_sleep(0.02);
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
  RAISE EXCEPTION 'expired authorization accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE atlas.delegated_agent_authorizations SET ends_at=NULL WHERE id=az;
 SELECT scope INTO revocation_scope FROM atlas.delegated_agent_authorizations WHERE id=az;
 UPDATE atlas.delegated_agent_authorizations SET scope='{}'::jsonb WHERE id=az;
 BEGIN PERFORM atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
  RAISE EXCEPTION 'broader target scope accepted' USING ERRCODE='XX000';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE atlas.delegated_agent_authorizations SET scope=revocation_scope WHERE id=az;
 -- No Course or revision should have changed after all negative attempts.
 IF (SELECT count(*) FROM atlas.teaching_course_units WHERE course_id=cid)<>before_count
  OR (SELECT count(*) FROM atlas.teaching_course_unit_revisions WHERE unit_id=old_unit)<>before_revision_count
 THEN RAISE EXCEPTION 'negative write altered originals';END IF;
 j:=atlas.apply_course_authoring_proposal_service_v1(key,inv,packet);
 uid:=(j->'items'->0->>'unitId')::uuid;
 IF uid IS NULL OR (j->'items'->1->>'unitId')::uuid<>old_unit OR
  j->'items'->1->>'revisionNumber'<>'3' OR
  (SELECT count(*) FROM atlas.teaching_course_units WHERE course_id=cid)<>before_count+1 OR
  (SELECT count(*) FROM atlas.teaching_course_unit_revisions WHERE unit_id=old_unit)<>before_revision_count+1 OR
  (SELECT count(*) FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id=inv)<>2 OR
  atlas.apply_course_authoring_proposal_service_v1(key,inv,packet) IS DISTINCT FROM j
 THEN RAISE EXCEPTION 'apply or exact receipt replay failed';END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id=inv
   AND recorded_by_auth_user_id<>current_setting('test.course_agent_owner')::uuid)
 THEN RAISE EXCEPTION 'approving principal attribution lost'; END IF;
 BEGIN UPDATE atlas.teaching_course_unit_revisions SET body_text='tampered' WHERE recorded_by_agent_invocation_id=inv;
  RAISE EXCEPTION 'delegated revision mutable' USING ERRCODE='XX000';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 PERFORM set_config('test.agent_receipt',j::text,true);
END $proof$;
-- Verify owner can keep writing and rearranging the same original using released self APIs.
SET LOCAL ROLE authenticated;
DO $manual$
DECLARE cid uuid:='11111111-1111-4111-8111-111111111111';
 uid uuid:='31111111-1111-4111-8111-111111111111';j jsonb;
BEGIN
 j:=public.shared_teaching_course_unit_save_self_api_v1(uid,gen_random_uuid(),3,'Fictional human follow-up');
 IF j->'material'->>'revisionNumber'<>'4' THEN RAISE EXCEPTION 'human follow-up failed';END IF;
 PERFORM public.shared_teaching_course_unit_move_self_api_v1(cid,uid,'down');
END $manual$;
RESET ROLE;
DO $replay$
BEGIN
 IF atlas.apply_course_authoring_proposal_service_v1(repeat('a',64),current_setting('test.agent_invocation')::uuid,
  current_setting('test.agent_packet')::jsonb) IS DISTINCT FROM current_setting('test.agent_receipt')::jsonb
 THEN RAISE EXCEPTION 'later human revision broke replay';END IF;
 IF EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions WHERE unit_id='31111111-1111-4111-8111-111111111111'
   AND revision_number=4 AND recorded_by_agent_invocation_id IS NOT NULL)
 THEN RAISE EXCEPTION 'human revision falsely attributed to agent';END IF;
END $replay$;
ROLLBACK;
