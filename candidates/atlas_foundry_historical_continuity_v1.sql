-- Atlas Foundry Historical Continuity v1
-- Single source-only SQL candidate for governed shared_ migration generation.
-- Linked to original historical workspace; does not create customer data.
-- Promotion requires disposable clone, genuine signed tests, explicit owner
-- production release authorization and current migration/custody receipt.
-- SOURCE ONLY. Do not run on the live database. Atlas release lane, Noel-owned.
-- Requires signed full-schema clone tests, source/custody review and manual production approval.
BEGIN;
CREATE OR REPLACE FUNCTION atlas.foundry_historical_eligible_self_v1(
 p_workspace_id text,p_principal_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','ledger','reality'
AS $body$
WITH evidence AS (
 SELECT e.workspace_id,
   split_part(e.envelope#>>'{provisional_subject,subject_ref}',':',2) AS subject_id,
   i.envelope#>'{root_facts,ledgers}' AS ledger_refs
 FROM foundry.events e JOIN foundry.events i
 ON i.workspace_id=e.workspace_id AND i.event_type='ATLAS_EVIDENCE_INVENTORIED'
 WHERE e.workspace_id=p_workspace_id AND e.sequence=1
   AND e.event_type='WORKSPACE_CREATED' AND e.workspace_id LIKE 'FW-%'
   AND e.inserted_at<'2026-10-23'::timestamptz
   AND e.envelope#>>'{provisional_subject,subject_ref}' LIKE 'reality.entities:%'
   -- Until a governed union-of-inventories contract exists, reject legacy
   -- workspaces with multiple snapshots rather than cherry-pick a subset.
   AND (SELECT count(*) FROM foundry.events inventory
        WHERE inventory.workspace_id=e.workspace_id
          AND inventory.event_type='ATLAS_EVIDENCE_INVENTORIED')=1
)
SELECT EXISTS(
 SELECT 1 FROM evidence src
 JOIN reality.entities entity ON entity.id::text=src.subject_id
  AND entity.identity_state='canonical'
 WHERE CASE WHEN jsonb_typeof(src.ledger_refs)='array'
      THEN jsonb_array_length(src.ledger_refs)>0 ELSE false END
   AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(CASE
      WHEN jsonb_typeof(src.ledger_refs)='array' THEN src.ledger_refs
      ELSE '[]'::jsonb END) item
    WHERE NOT EXISTS (
      SELECT 1 FROM ledger.ledgers l
      JOIN atlas.principal_ledger_authorities pa ON pa.ledger_id=l.id
      WHERE l.id::text=item->>'id'
        AND l.subject_entity_id=entity.id AND l.ledger_state='active'
        AND pa.principal_id=p_principal_id AND pa.status='active'
        AND pa.authority_kind='root_governing'
    )
   )
   -- A recovered private archive additionally requires at least one
   -- inventoried Ledger whose active root governance is exclusive to the
   -- claimant. Shared Ledger authority alone never exposes the archive.
   -- Multi-root institutional archives need a separate human custody
   -- adjudication, not a silent workspace assignment.
   AND EXISTS (
     SELECT 1 FROM jsonb_array_elements(src.ledger_refs) item
     JOIN ledger.ledgers root_ledger ON root_ledger.id::text=item->>'id'
       AND root_ledger.subject_entity_id=entity.id
     JOIN atlas.principal_ledger_authorities own
       ON own.ledger_id=root_ledger.id
       AND own.principal_id=p_principal_id
       AND own.authority_kind='root_governing' AND own.status='active'
     WHERE NOT EXISTS (
       SELECT 1 FROM atlas.principal_ledger_authorities another
       WHERE another.ledger_id=root_ledger.id
         AND another.authority_kind='root_governing'
         AND another.status='active'
         AND another.principal_id<>p_principal_id
     )
   )
);
$body$;
CREATE OR REPLACE FUNCTION atlas.list_foundry_historical_recovery_candidates_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1(); items jsonb;
BEGIN
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'workspaceId',e.workspace_id,
   'subjectLabel',e.envelope#>>'{provisional_subject,label}',
   'eventCount',(SELECT count(*) FROM foundry.events h WHERE h.workspace_id=e.workspace_id)
 ) ORDER BY e.workspace_id),'[]'::jsonb) INTO items
 FROM foundry.events e
 WHERE e.sequence=1 AND e.event_type='WORKSPACE_CREATED'
   AND NOT EXISTS (SELECT 1 FROM foundry.workspace_authority_registry_v1 r
                   WHERE r.workspace_id=e.workspace_id)
   AND atlas.foundry_historical_eligible_self_v1(e.workspace_id,actor);
 RETURN jsonb_build_object('ok',true,'contractVersion','foundry_historical_recovery_candidates_v1',
    'items',items,'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

CREATE OR REPLACE FUNCTION atlas.recover_foundry_historical_workspace_self_api_v1(
 p_workspace_id text,p_request_id uuid,p_confirm_original_history boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1();
 previous foundry.workspace_authority_registry_v1%rowtype;
 source_event foundry.events%rowtype;
 next_sequence bigint; appended jsonb;
BEGIN
 IF p_workspace_id IS NULL OR p_request_id IS NULL
    OR p_confirm_original_history IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Explicit signed acknowledgement required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
 SELECT * INTO previous FROM foundry.workspace_authority_registry_v1
 WHERE workspace_id=p_workspace_id FOR UPDATE;
 IF FOUND THEN
   IF previous.owner_principal_id=actor AND previous.creation_request_id=p_request_id
      AND previous.revoked_at IS NULL AND previous.suspended_at IS NULL
   THEN RETURN jsonb_build_object('ok',true,'replayed',true,
     'workspaceId',p_workspace_id,'canonicalAtlasMutation',false,'aiCarrierAccess',false); END IF;
   RAISE EXCEPTION 'Existing workspace cannot be reassigned' USING ERRCODE='42501';
 END IF;
 IF NOT atlas.foundry_historical_eligible_self_v1(p_workspace_id,actor)
 THEN RAISE EXCEPTION 'Historical workspace recovery not authorized' USING ERRCODE='42501'; END IF;
 SELECT * INTO source_event FROM foundry.events
 WHERE workspace_id=p_workspace_id AND sequence=1 AND event_type='WORKSPACE_CREATED';
 INSERT INTO foundry.workspace_authority_registry_v1(
   workspace_id,creation_request_id,owner_principal_id,
   provisional_subject_label,provisional_field,subject_identity_state,
   custody_scope_kind,custody_review_state,custody_basis_refs,
   created_by_principal_id
 ) VALUES(
   p_workspace_id,p_request_id,actor,
   left(coalesce(nullif(btrim(source_event.envelope#>>'{provisional_subject,label}'),''),
      'Recovered subject'),500),
   left(coalesce(nullif(btrim(source_event.envelope->>'provisional_field'),''),
      'Historical Foundry inquiry'),2000),
   'provisional','documented_external','pending',
   ARRAY['foundry.events:'||p_workspace_id||':1',
         'foundry.events:'||p_workspace_id||':2'],actor
 );
 SELECT max(sequence)+1 INTO next_sequence FROM foundry.events
 WHERE workspace_id=p_workspace_id;
 appended:=foundry.append_event(jsonb_build_object(
   'workspace_id',p_workspace_id,'sequence',next_sequence,
   'event_id','historical-recovery-'||p_request_id::text,
   'event_type','HISTORICAL_WORKSPACE_RECOVERED',
   'payload',jsonb_build_object('request_id',p_request_id,
      'actor_principal_id',actor,'original_event_count',next_sequence-1,
      'historical_events_unchanged',true,'canonical_mutation',false),
   'basis_refs',jsonb_build_array('foundry.events:'||p_workspace_id||':1',
       'foundry.events:'||p_workspace_id||':2'),
   'authority','signed_legacy_claim_with_all_historical_ledger_governance',
   'actor_kind','human','protocol_version','0.1',
   'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
       'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
 ));
 IF appended->>'status'<>'APPENDED'
 THEN RAISE EXCEPTION 'Recovery receipt not appended' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'replayed',false,'workspaceId',p_workspace_id,
   'originalEventCount',next_sequence-1,'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

CREATE OR REPLACE FUNCTION public.list_foundry_historical_recovery_candidates_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $body$ SELECT atlas.list_foundry_historical_recovery_candidates_self_api_v1(); $body$;
CREATE OR REPLACE FUNCTION public.recover_foundry_historical_workspace_self_api_v1(
 p_workspace_id text,p_request_id uuid,p_confirm_original_history boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $body$ SELECT atlas.recover_foundry_historical_workspace_self_api_v1(
 p_workspace_id,p_request_id,p_confirm_original_history); $body$;
REVOKE ALL ON FUNCTION atlas.foundry_historical_eligible_self_v1(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.list_foundry_historical_recovery_candidates_self_api_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.list_foundry_historical_recovery_candidates_self_api_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_historical_recovery_candidates_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_foundry_historical_recovery_candidates_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.recover_foundry_historical_workspace_self_api_v1(text,uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.list_foundry_workspace_history_self_api_v1(
 p_workspace_id text,p_after_sequence bigint DEFAULT 0,p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1();
 items jsonb; take_rows integer:=least(25,greatest(1,coalesce(p_limit,20)));
 cursor_seq bigint:=greatest(0,coalesce(p_after_sequence,0));
BEGIN
 IF NOT EXISTS (SELECT 1 FROM foundry.workspace_authority_registry_v1 r
  WHERE r.workspace_id=p_workspace_id AND r.owner_principal_id=actor
   AND r.revoked_at IS NULL AND r.suspended_at IS NULL
   AND r.custody_review_state NOT IN ('revoked','suspended'))
 THEN RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'eventId',e.event_id,'sequence',e.sequence,'eventType',e.event_type,
   'recordedAt',e.inserted_at,
   'summary',coalesce(nullif(e.envelope#>>'{payload,summary}',''),
       nullif(e.envelope->>'summary',''),
       nullif(e.envelope#>>'{payload,original_text}',''),
       nullif(e.envelope#>>'{payload,description}','')),
   'sourceStatus',CASE WHEN e.event_type='foundry_reality_input_v1'
     THEN 'unresolved_evidence'
     WHEN e.event_type='HISTORICAL_WORKSPACE_RECOVERED'
     THEN 'recovery_receipt' ELSE 'historical_source' END
 ) ORDER BY e.sequence),'[]'::jsonb) INTO items
 FROM (SELECT * FROM foundry.events WHERE workspace_id=p_workspace_id
   AND sequence>cursor_seq ORDER BY sequence LIMIT take_rows) e;
 RETURN jsonb_build_object('ok',true,'contractVersion','foundry_workspace_history_v1',
   'workspaceId',p_workspace_id,'items',items,
   'totalEvents',(SELECT count(*) FROM foundry.events WHERE workspace_id=p_workspace_id),
   'nextAfterSequence',CASE WHEN jsonb_array_length(items)=take_rows
      THEN (SELECT max((v->>'sequence')::bigint) FROM jsonb_array_elements(items) v)
      ELSE NULL END,
   'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

-- Original envelope remains retrievable on an explicit click, not loaded
-- wholesale into an Index. Every event read rechecks the signed owner.
CREATE OR REPLACE FUNCTION atlas.get_foundry_workspace_event_self_api_v1(
 p_workspace_id text,p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1();
 found_event foundry.events%rowtype;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM foundry.workspace_authority_registry_v1 r
  WHERE r.workspace_id=p_workspace_id AND r.owner_principal_id=actor
   AND r.revoked_at IS NULL AND r.suspended_at IS NULL
   AND r.custody_review_state NOT IN ('revoked','suspended'))
 THEN RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501'; END IF;
 SELECT * INTO found_event FROM foundry.events
 WHERE workspace_id=p_workspace_id AND event_id=p_event_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Event not accessible' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','foundry_workspace_event_v1',
  'workspaceId',p_workspace_id,'eventId',p_event_id,
  'envelope',found_event.envelope,
  'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

-- A reference to existing Implementation records is NOT a practitioner
-- source grant, a replacement institutional case, or a new Ledger.
CREATE OR REPLACE FUNCTION atlas.get_foundry_existing_implementation_context_self_api_v1(
 p_workspace_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','ledger','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1();
 subject_id text; personal_case uuid; ledger_items jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM foundry.workspace_authority_registry_v1 r
  WHERE r.workspace_id=p_workspace_id AND r.owner_principal_id=actor
   AND r.revoked_at IS NULL AND r.suspended_at IS NULL)
 THEN RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501'; END IF;
 SELECT split_part(e.envelope#>>'{provisional_subject,subject_ref}',':',2)
 INTO subject_id FROM foundry.events e
 WHERE e.workspace_id=p_workspace_id AND e.sequence=1
   AND (e.envelope#>>'{provisional_subject,subject_ref}') LIKE 'reality.entities:%';
 SELECT c.id INTO personal_case FROM atlas.implementation_cases c
 JOIN atlas.principals p ON p.person_id=c.personal_subject_person_entity_id
 WHERE p.id=actor AND c.case_origin='personal_atlas'
   AND c.state<>'cancelled' ORDER BY c.created_at DESC LIMIT 1;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ledgerId',l.id,'ledgerName',l.name,
   'onboardingCaseId',l.onboarding_case_id,
   'onboardingState',o.onboarding_state
 ) ORDER BY l.name),'[]'::jsonb) INTO ledger_items
 FROM ledger.ledgers l
 JOIN atlas.principal_ledger_authorities authority
 ON authority.ledger_id=l.id AND authority.principal_id=actor
 AND authority.authority_kind='root_governing' AND authority.status='active'
 LEFT JOIN ledger.onboarding_cases o ON o.id=l.onboarding_case_id
 WHERE l.subject_entity_id::text=subject_id AND l.ledger_state='active';
 RETURN jsonb_build_object('ok',true,
   'contractVersion','foundry_existing_implementation_context_v1',
   'personalImplementationCaseId',personal_case,'ledgers',ledger_items,
   'sourceAccessGrant',false,'caseWasCreated',false,'ledgerWasCreated',false,
   'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

CREATE OR REPLACE FUNCTION public.list_foundry_workspace_history_self_api_v1(
 p_workspace_id text,p_after_sequence bigint DEFAULT 0,p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog','atlas'
AS $body$ SELECT atlas.list_foundry_workspace_history_self_api_v1(
 p_workspace_id,p_after_sequence,p_limit); $body$;
CREATE OR REPLACE FUNCTION public.get_foundry_workspace_event_self_api_v1(
 p_workspace_id text,p_event_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog','atlas'
AS $body$ SELECT atlas.get_foundry_workspace_event_self_api_v1(
 p_workspace_id,p_event_id); $body$;
CREATE OR REPLACE FUNCTION public.get_foundry_existing_implementation_context_self_api_v1(
 p_workspace_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog','atlas'
AS $body$ SELECT atlas.get_foundry_existing_implementation_context_self_api_v1(
 p_workspace_id); $body$;
REVOKE ALL ON FUNCTION atlas.list_foundry_workspace_history_self_api_v1(text,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.get_foundry_workspace_event_self_api_v1(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.get_foundry_existing_implementation_context_self_api_v1(text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.list_foundry_workspace_history_self_api_v1(text,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_foundry_workspace_event_self_api_v1(text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_foundry_existing_implementation_context_self_api_v1(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_workspace_history_self_api_v1(text,bigint,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.get_foundry_workspace_event_self_api_v1(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.get_foundry_existing_implementation_context_self_api_v1(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_foundry_workspace_history_self_api_v1(text,bigint,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_foundry_workspace_event_self_api_v1(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_foundry_existing_implementation_context_self_api_v1(text) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.identify_foundry_as_personal_implementation_source_self_api_v1(
 p_workspace_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth'
AS $body$
DECLARE actor uuid:=atlas.foundry_current_signed_principal_v1();
 owner_user uuid:=auth.uid();
 case_id uuid; source_id uuid;
 record_label text;
BEGIN
 IF p_workspace_id IS NULL OR length(btrim(p_workspace_id))=0
 THEN RAISE EXCEPTION 'Workspace required' USING ERRCODE='22023'; END IF;
 SELECT w.provisional_subject_label INTO record_label
 FROM foundry.workspace_authority_registry_v1 w
 WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=actor
   AND w.revoked_at IS NULL AND w.suspended_at IS NULL
   AND w.custody_review_state NOT IN ('revoked','suspended');
 IF NOT FOUND THEN RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501'; END IF;
 SELECT c.id INTO case_id
 FROM atlas.implementation_cases c
 JOIN atlas.principals p ON p.person_id=c.personal_subject_person_entity_id
 WHERE p.id=actor AND c.case_origin='personal_atlas'
   AND c.state NOT IN ('closed','cancelled')
 ORDER BY c.created_at DESC LIMIT 1;
 IF case_id IS NULL THEN
   RAISE EXCEPTION 'No active existing personal Implementation case'
      USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
     'implementation-foundry-source:'||case_id::text||':'||p_workspace_id,0));
 SELECT s.id INTO source_id
 FROM atlas.implementation_case_sources s
 WHERE s.implementation_case_id=case_id
   AND s.provider_key='foundry_workspace'
   AND s.metadata->>'foundryWorkspaceId'=p_workspace_id
   AND s.source_state<>'removed'
 ORDER BY s.created_at LIMIT 1;
 IF source_id IS NULL THEN
   INSERT INTO atlas.implementation_case_sources (
      implementation_case_id,provider_key,display_label,source_state,
      requirement_state,identified_by_user_id,authorization_context,metadata)
   VALUES (
     case_id,'foundry_workspace',
     left('Foundry history — '||record_label,160),
     'identified','unclassified',owner_user,
     jsonb_build_object('sourceReadAuthorized',false,
       'authorizationDecision','not_granted'),
     jsonb_build_object('foundryWorkspaceId',p_workspace_id,
       'sourceCustody','historical_foundry',
       'implementationReferenceOnly',true,
       'noCanonicalMutation',true)
   ) RETURNING id INTO source_id;
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','foundry_personal_implementation_source_v1',
   'implementationCaseId',case_id,'implementationCaseSourceId',source_id,
   'sourceState','identified','sourceReadAuthorized',false,
   'caseWasCreated',false,'ledgerWasCreated',false,
   'canonicalAtlasMutation',false,'aiCarrierAccess',false);
END;$body$;

CREATE OR REPLACE FUNCTION public.identify_foundry_as_personal_implementation_source_self_api_v1(
 p_workspace_id text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $body$
 SELECT atlas.identify_foundry_as_personal_implementation_source_self_api_v1(p_workspace_id);
$body$;
REVOKE ALL ON FUNCTION atlas.identify_foundry_as_personal_implementation_source_self_api_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.identify_foundry_as_personal_implementation_source_self_api_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.identify_foundry_as_personal_implementation_source_self_api_v1(text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.identify_foundry_as_personal_implementation_source_self_api_v1(text)
 TO authenticated;
COMMIT;
