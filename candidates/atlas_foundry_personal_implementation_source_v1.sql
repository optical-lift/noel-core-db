-- Foundry → existing Personal Atlas Implementation Case source handoff.
-- Signed owner-only, source identification (NOT source access authorization).
-- Source-only candidate. Included in the governed historical-continuity bundle.
BEGIN;
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
