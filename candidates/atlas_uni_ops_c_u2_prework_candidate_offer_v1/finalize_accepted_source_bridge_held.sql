-- UNI-OPS-01 Option C / U2B HELD BRIDGE. Not a migration.
-- Requires U2A, U1B, R02 source and R01 native original writer.
-- This is an explicit signed GOVERNOR-finalization bridge, NOT an autonomous
-- executor. Existing R02 public direct approval is NOT retired by this file.
-- Do not release until the old direct writer is governed/retired so worker
-- choice cannot be bypassed elsewhere. Every operation is one DB transaction.

CREATE FUNCTION atlas.finalize_accepted_governed_prework_self_api_v1(
 p_offer_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $finalize$
DECLARE
 v_preview atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_root record;
 v_result jsonb;
 v_work_id uuid;
 v_alloc uuid;
BEGIN
 IF p_offer_id IS NULL THEN
   RAISE EXCEPTION 'Exact accepted candidate reference required'
     USING ERRCODE='42501';
 END IF;
 -- No unscoped root/candidate list. Determine only the caller-supplied
 -- known offer's custody, then demand current signed root before return.
 SELECT * INTO v_preview FROM atlas.governed_prework_candidate_offers_v1
 WHERE id=p_offer_id;
 IF v_preview.id IS NULL THEN
   RAISE EXCEPTION 'Offer unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_root FROM atlas.require_governed_farm_rulebook_root_v1(
   v_preview.organization_id,v_preview.ledger_id,v_preview.farm_id,
   v_preview.source_rule_id);
 IF v_root.actor_person_id IS DISTINCT FROM v_preview.offered_by_person_id THEN
   RAISE EXCEPTION 'Only the original current native root may finalize'
     USING ERRCODE='42501';
 END IF;

 -- This lock is also held by U1B property pause and by U2A candidate offer.
 -- A root cannot knowingly finalize against an uncommitted policy pause.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u1b:'||v_preview.organization_id::text||':'||
  v_preview.ledger_id::text||':'||v_preview.farm_id::text||':'||
  v_preview.source_rule_id::text||':property',0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  'u2:offer:'||v_preview.organization_id::text||':'||
  v_preview.ledger_id::text||':'||v_preview.farm_id::text||':'||
  v_preview.source_rule_id::text,0));
 SELECT * INTO v_offer FROM atlas.governed_prework_candidate_offers_v1
 WHERE id=p_offer_id FOR UPDATE;
 IF v_offer.id IS NULL OR
    v_offer.organization_id IS DISTINCT FROM v_preview.organization_id OR
    v_offer.source_candidate_id IS DISTINCT FROM v_preview.source_candidate_id OR
    v_offer.offered_by_person_id IS DISTINCT FROM v_root.actor_person_id THEN
   RAISE EXCEPTION 'Offer identity changed' USING ERRCODE='42501';
 END IF;

 IF v_offer.offer_state='fulfilled' AND v_offer.original_work_item_id IS NOT NULL THEN
   -- A completed response has already been converted by this bridge.
   -- No duplicate original or additional Person/Clock responsibility.
   RETURN pg_catalog.jsonb_build_object('ok',true,
    'contractVersion','governed_prework_finalized_v1',
    'replayed',true,'offerId',v_offer.id,
    'workItemId',v_offer.original_work_item_id,
    'originalWorkCreatedNow',false,'workerAcceptedFirst',true);
 END IF;
 IF v_offer.offer_state<>'accepted' OR v_offer.responded_at IS NULL
    OR v_offer.responding_principal_id IS NULL
    OR v_offer.response_action_id IS NULL THEN
   RAISE EXCEPTION 'Worker must independently accept before original Work'
      USING ERRCODE='42501';
 END IF;
 IF NOT atlas.governed_prework_offer_still_admissible_v1(v_offer.id)
 THEN
   RAISE EXCEPTION 'Current policy, native Person, workday, capacity or source changed'
     USING ERRCODE='42501';
 END IF;

 -- Never infer authorization from the response. Reuse R02/R01's separately
 -- signed current root, native accepted scope, original collision checks,
 -- source Result contract, one-allocation and Work-day writer.
 -- The offer UUID is the sole stable original source action.
 v_result:=atlas.governor_approve_rhythm_opportunity_self_api_v1(
  v_offer.organization_id,v_offer.ledger_id,
  v_offer.accepted_standing_scope_id,
  'continuing_care_actual_v1',v_offer.source_candidate_id,
  v_offer.reason,v_offer.first_service_day,v_offer.campaign_end_date,
  v_offer.approved_iso_weekdays,v_offer.id);
 IF v_result->>'ok' IS DISTINCT FROM 'true'
   OR v_result->>'contractVersion' IS DISTINCT FROM 'governed_rhythm_approval_v1'
   OR v_result->>'actionId' IS DISTINCT FROM v_offer.id::text
   OR v_result->>'candidateId' IS DISTINCT FROM v_offer.source_candidate_id::text
   OR v_result->>'newOriginalWorkCreated' IS DISTINCT FROM 'true'
   OR v_result->>'existingOpenServing' IS DISTINCT FROM 'false'
   OR v_result->>'existingAction' IS DISTINCT FROM 'false'
   OR v_result->>'noPhysicalResultInferred' IS DISTINCT FROM 'true'
   OR coalesce(v_result->>'workItemId','') !~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
   RAISE EXCEPTION 'Original writer did not create exactly one new source Work'
     USING ERRCODE='23514';
 END IF;
 v_work_id:=(v_result->>'workItemId')::uuid;

 SELECT a.id INTO v_alloc FROM atlas.work_allocations a
 JOIN atlas.work_items w ON w.id=a.work_item_id
 JOIN atlas.company_work_native_ledger_relevance rel
  ON rel.organization_id=w.organization_id AND rel.work_item_id=w.id
   AND rel.ledger_id=v_offer.ledger_id AND rel.attribution_state='active'
 WHERE w.id=v_work_id AND w.organization_id=v_offer.organization_id
  AND w.source_object_type='rhythm_state'
  AND w.source_object_id=v_offer.source_candidate_id AND w.work_state='open'
  AND a.assignee_canonical_person_id=v_offer.target_person_id
  AND a.allocation_role='responsible' AND a.state='active'
 LIMIT 1;
 IF v_alloc IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.work_execution_plans p
   WHERE p.work_item_id=v_work_id AND p.organization_id=v_offer.organization_id
    AND p.responsible_allocation_id=v_alloc
    AND p.plan_state='active'
    AND p.planned_service_date=v_offer.first_service_day
 ) THEN
   RAISE EXCEPTION 'Canonical original, allocation and chosen Person day did not agree'
     USING ERRCODE='23514';
 END IF;

 UPDATE atlas.governed_prework_candidate_offers_v1
 SET offer_state='fulfilled',original_work_item_id=v_work_id
 WHERE id=v_offer.id AND offer_state='accepted';
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','governed_prework_finalized_v1',
  'replayed',false,'offerId',v_offer.id,'workItemId',v_work_id,
  'acceptedByPersonId',v_offer.target_person_id,
  'originalWorkCreatedNow',true,'workerAcceptedFirst',true,
  'noPhysicalConditionAsserted',true,'principalClockAdmitted',false,
  'nextOriginalNotPrecreated',true);
END;
$finalize$;
REVOKE ALL ON FUNCTION atlas.finalize_accepted_governed_prework_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.finalize_accepted_governed_prework_self_api_v1(
 p_offer_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transport$
 SELECT atlas.finalize_accepted_governed_prework_self_api_v1(p_offer_id);
$transport$;
REVOKE ALL ON FUNCTION public.finalize_accepted_governed_prework_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_accepted_governed_prework_self_api_v1(uuid)
 TO authenticated;

-- End U2B. Future autonomous evaluator must rely on source-owned durable
-- standing root authority and a protected execution identity, not impersonate
-- the last governor session. Do not enable this without closing R02 bypass.
