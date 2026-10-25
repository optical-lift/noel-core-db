-- SOURCE ONLY. Same governed release as atlas_foundry_legacy_signed_claim_v1.sql.
-- The owner must already be in foundry.workspace_authority_registry_v1.
BEGIN;
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
COMMIT;
