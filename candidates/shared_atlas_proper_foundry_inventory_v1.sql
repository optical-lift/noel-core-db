-- SOURCE-ONLY candidate, shared_ lane: Atlas Proper operator discovery inventory.
-- Read-only projection of already existing canonical businesses, native Ledgers,
-- Ledger onboarding and Foundry SOURCE COUNTS. Never returns private envelopes.
-- Does not claim custody, create an implementation case or attach a source.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.implementation_foundry_discovery_inventory_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','foundry','ledger','reality','pg_temp'
AS $body$
DECLARE
 v_user uuid:=auth.uid();
 v_session uuid;
 v_result jsonb;
BEGIN
 IF v_user IS NULL
   OR NOT coalesce(atlas.implementation_practitioner_authorized_self_v1(),false)
   OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_user
       AND u.is_anonymous=false
       AND (u.banned_until IS NULL OR u.banned_until<=now()))
 THEN
   RAISE EXCEPTION 'Active Atlas implementation practitioner required'
     USING ERRCODE='42501';
 END IF;
 BEGIN
   v_session:=nullif(auth.jwt()->>'session_id','')::uuid;
 EXCEPTION WHEN OTHERS THEN
   RAISE EXCEPTION 'Invalid signed implementation session'
     USING ERRCODE='42501';
 END;
 IF v_session IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    WHERE s.id=v_session AND s.user_id=v_user
      AND (s.not_after IS NULL OR s.not_after>now())
 ) THEN
   RAISE EXCEPTION 'Revoked or missing signed implementation session'
     USING ERRCODE='42501';
 END IF;

 WITH original_headers AS (
   SELECT f.workspace_id,
     coalesce(
       nullif(f.envelope #>> '{payload,subject,entity_id}',''),
       nullif(split_part(f.envelope #>> '{provisional_subject,subject_ref}',':',2),'')
     ) AS raw_subject,
     nullif(f.envelope #>> '{payload,existing_ledger_id}','') AS raw_ledger
   FROM foundry.events f
   WHERE f.sequence=1 AND f.event_type='WORKSPACE_CREATED'
 ),
 verified_refs AS (
   SELECT h.workspace_id,
     h.raw_subject::uuid AS subject_id,
     CASE WHEN h.raw_ledger ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       THEN h.raw_ledger::uuid ELSE NULL END AS asserted_ledger_id,
     h.raw_ledger IS NOT NULL AS has_asserted_ledger
   FROM original_headers h
   WHERE h.raw_subject ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 ),
 qualified AS (
   SELECT v.workspace_id,v.subject_id
   FROM verified_refs v
   JOIN reality.entities e ON e.id=v.subject_id
     AND e.identity_state='canonical'
     AND e.entity_kind IN ('business','organization')
   WHERE EXISTS (
     SELECT 1 FROM ledger.ledgers l
     WHERE l.subject_entity_id=e.id AND l.ledger_state='active'
   )
   AND (NOT v.has_asserted_ledger OR
     (v.asserted_ledger_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM ledger.ledgers l
       WHERE l.id=v.asserted_ledger_id AND l.subject_entity_id=e.id
     ))
   )
 ),
 inventory AS (
   SELECT e.id,e.display_name
   FROM reality.entities e
   WHERE EXISTS (SELECT 1 FROM qualified q WHERE q.subject_id=e.id)
 )
 SELECT jsonb_build_object(
   'ok',true,
   'contractVersion','atlas_proper_discovery_inventory_v1',
   'inventoryState','read_only_evidence_index',
   'caseCreated',false,
   'sourceReadAuthorized',false,
   'canonicalMutation',false,
   'aiCarrierAccess',false,
   'unresolvedArchiveCount',(
     SELECT count(*) FROM original_headers h
     WHERE NOT EXISTS (SELECT 1 FROM qualified q WHERE q.workspace_id=h.workspace_id)
   ),
   'items',coalesce((
     SELECT jsonb_agg(
       jsonb_build_object(
         'subjectEntityId',i.id,
         'subjectLabel',i.display_name,
         'ledgers',coalesce((
           SELECT jsonb_agg(jsonb_build_object(
             'ledgerId',l.id,'ledgerName',l.name,
             'onboardingCaseId',o.id,'onboardingState',o.onboarding_state
           ) ORDER BY l.name,l.id)
           FROM ledger.ledgers l
           JOIN ledger.onboarding_cases o ON o.id=l.onboarding_case_id
           WHERE l.subject_entity_id=i.id AND l.ledger_state='active'
         ),'[]'::jsonb),
         'archives',coalesce((
           SELECT jsonb_agg(jsonb_build_object(
             'workspaceId',q.workspace_id,
             'eventCount',(
               SELECT count(*) FROM foundry.events ev WHERE ev.workspace_id=q.workspace_id
             ),
             'lastRecordedAt',(
               SELECT max(ev.inserted_at) FROM foundry.events ev
               WHERE ev.workspace_id=q.workspace_id
             ),
             'sourceAccess','not_granted',
             'reviewState','awaiting_scoped_source_review'
           ) ORDER BY q.workspace_id)
           FROM qualified q WHERE q.subject_id=i.id
         ),'[]'::jsonb),
         'caseAssociation','not_established',
         'requirementStatus','not_yet_adjudicated',
         'originalTestimonyIncluded',false
       ) ORDER BY i.display_name,i.id
     ) FROM inventory i
   ),'[]'::jsonb)
 ) INTO v_result;

 RETURN v_result;
END;$body$;

CREATE OR REPLACE FUNCTION public.implementation_foundry_discovery_inventory_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $body$
 SELECT atlas.implementation_foundry_discovery_inventory_self_api_v1();
$body$;

REVOKE ALL ON FUNCTION atlas.implementation_foundry_discovery_inventory_self_api_v1()
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.implementation_foundry_discovery_inventory_self_api_v1()
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.implementation_foundry_discovery_inventory_self_api_v1()
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.implementation_foundry_discovery_inventory_self_api_v1()
 TO authenticated;
COMMIT;
