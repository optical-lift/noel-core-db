-- Disposable combined candidate; immutable sources 4036e09e206e798f4ff7bc197268264aa8cb56ee and f66559c99f8bc7ef5cb7b9102e43c89cb85e23bf.
-- HELD standing private Course grant candidate. Review/test before migration.
BEGIN;
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
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp()))
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
     AND x.principal_id=a.principal_id AND x.authorization_state='active' AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp()))
 ) OR atlas.private_atlas_carrier_standing_grant_current_v1(p_authorization_id);
$function$;

CREATE OR REPLACE FUNCTION atlas.save_private_course_draft_service_v1(p_token_hash text, p_course uuid, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
   OR (cred.expires_at IS NOT NULL AND cred.expires_at<=clock_timestamp())
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
END $function$;

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
  AND authorization_state='active' AND (ends_at IS NULL OR ends_at>clock_timestamp());
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

CREATE OR REPLACE FUNCTION public.shared_private_atlas_carrier_status_self_api_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
    AND cr.credential_state='active' AND cr.begins_at<=clock_timestamp() AND cr.expires_at IS NOT DISTINCT FROM a.ends_at AND (cr.expires_at IS NULL OR cr.expires_at>clock_timestamp())
    AND cr.metadata->>'privateCarrierCredentialV1'='true'
    AND a.authorization_state='active' AND a.begins_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND c.status='active' AND EXISTS(SELECT 1 FROM atlas.principals WHERE id=pid AND status='active'))) END);
END $function$;

REVOKE ALL ON FUNCTION public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_private_atlas_carrier_enroll_standing_self_api_v1(uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.private_atlas_carrier_standing_grant_current_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
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
  OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
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
