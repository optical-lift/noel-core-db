-- HELD: scoped governor preflight and thin authenticated REST transport.
-- The impact token is derived from existing source dependency snapshot.
CREATE OR REPLACE FUNCTION atlas.governor_historical_retirement_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_review_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $preflight$
DECLARE
 v_actor uuid;
 v_review atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 v_impact jsonb;
 v_blockers integer;
BEGIN
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF v_actor IS NULL OR p_review_id IS NULL THEN
   RAISE EXCEPTION 'Exact signed native governor and review required'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_review FROM atlas.historical_self_adoption_review_events_v1 h
 WHERE h.id=p_review_id AND h.organization_id=p_organization_id
 AND h.ledger_id=p_ledger_id AND h.event_kind='governor_reviewed'
 AND h.outcome='obsolete_cancelled';
 IF v_review.id IS NULL
 OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
   WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.work_item_id=v_review.work_item_id AND r.attribution_state='active')
 OR NOT EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 l
   JOIN atlas.work_allocations a ON a.id=l.allocation_id
   WHERE l.id=v_review.parent_event_id AND l.event_kind='person_confirmed'
     AND l.ledger_id=p_ledger_id AND l.organization_id=p_organization_id
     AND l.work_item_id=v_review.work_item_id
     AND l.allocation_id=v_review.allocation_id
     AND a.work_item_id=v_review.work_item_id
     AND a.organization_id=p_organization_id
     AND a.establishment_basis_kind='self_adoption')
 THEN RAISE EXCEPTION 'Exact reviewed historical original and current Ledger required'
 USING ERRCODE='42501'; END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_review.work_item_id);
 IF v_impact IS NULL THEN RAISE EXCEPTION 'Original Work not found'
 USING ERRCODE='42501'; END IF;
 v_blockers:=jsonb_array_length(v_impact->'requirements')
   +jsonb_array_length(v_impact->'relations')
   +jsonb_array_length(v_impact->'pendingOfferIds')
   +jsonb_array_length(v_impact->'projectionIds')
   +jsonb_array_length(v_impact->'executionResultIds')
   +jsonb_array_length(v_impact->'activeTimeContractIds')
   +jsonb_array_length(v_impact->'automaticUnwind'->'activeAdapterIds')
   +(SELECT count(*) FROM atlas.work_allocations a
     WHERE a.work_item_id=v_review.work_item_id AND a.state='active'
       AND a.id IS DISTINCT FROM v_review.allocation_id)
   +(SELECT count(*) FROM atlas.work_execution_plans p
     WHERE p.work_item_id=v_review.work_item_id
       AND p.plan_state IN ('active','needs_replan')
       AND p.responsible_allocation_id IS DISTINCT FROM v_review.allocation_id);
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','native_historical_work_retirement_v1',
  'workItemId',v_review.work_item_id,'reviewId',v_review.id,
  'workState',v_impact->>'workState',
  'impact',v_impact,'impactToken',md5(v_impact::text),
  'blockingDependencyCount',v_blockers,
  'retirable',v_impact->>'workState'='open' AND v_blockers=0,
  'physicalPerformanceClaimed',false,'acceptedResultCreated',false);
END; $preflight$;
REVOKE ALL ON FUNCTION atlas.governor_historical_retirement_preflight_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_historical_retirement_preflight_self_api_v1(
 uuid,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.governor_historical_retirement_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_review_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $rpc$
 SELECT atlas.governor_historical_retirement_preflight_self_api_v1(
   p_organization_id,p_ledger_id,p_review_id);
$rpc$;
CREATE OR REPLACE FUNCTION public.governor_retire_historical_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_review_id uuid,
 p_impact_token text,p_action_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $rpc$
 SELECT atlas.governor_retire_historical_work_self_api_v1(
   p_organization_id,p_ledger_id,p_review_id,p_impact_token,p_action_id);
$rpc$;
REVOKE ALL ON FUNCTION public.governor_historical_retirement_preflight_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_historical_retirement_preflight_self_api_v1(
 uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) TO authenticated;
