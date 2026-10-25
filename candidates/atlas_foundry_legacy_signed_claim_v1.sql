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
COMMIT;
