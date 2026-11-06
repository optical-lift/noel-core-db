-- UNI-OPS-01 P3 / governed owner attention reader, HELD SOURCE ONLY.
-- Replaces neither the Ledger Work writer nor the legacy owner review
-- task interface. It reads ONLY source-qualified pending ATTENTION,
-- not a roster, worker notebook, offer list, accepted Work or scheduling.
-- Requires U1B true native farm -> governing Company Ledger custody.
-- U1B and new P3 sources ARE NOT INSTALLED in live Noel production.

DO $prerequisite$
BEGIN
 IF pg_catalog.to_regclass('atlas.farm_crop_ledger_custody_v1') IS NULL
    OR pg_catalog.to_regprocedure(
      'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)') IS NULL
    OR pg_catalog.to_regclass('atlas.journal_event_index') IS NULL
    OR pg_catalog.to_regclass('atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NULL
 THEN RAISE EXCEPTION
    'P3 pending-attention reader requires true U1B native Ledger custody and real Journal';
 END IF;
END;
$prerequisite$;

CREATE FUNCTION atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(
 p_farm_id uuid,
 p_ledger_id uuid,
 p_from_date date DEFAULT (CURRENT_DATE-30),
 p_through_date date DEFAULT CURRENT_DATE
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $read$
DECLARE
 v_farm atlas.farms%ROWTYPE;
 v_root uuid;
 v_items jsonb:='[]'::jsonb;
 v_has_more boolean:=false;
BEGIN
 IF auth.uid() IS NULL
    OR atlas.current_person_id_v1() IS NULL
    OR p_farm_id IS NULL OR p_ledger_id IS NULL
    OR p_from_date IS NULL OR p_through_date IS NULL
    OR p_through_date<p_from_date
    OR p_through_date-p_from_date>60
 THEN RAISE EXCEPTION 'Exact bounded signed farm Ledger owner window required'
    USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_farm FROM atlas.farms f
 WHERE f.id=p_farm_id AND f.status='active';
 IF v_farm.id IS NULL THEN
  RAISE EXCEPTION 'Exact active source Farm unavailable'
   USING ERRCODE='42501';
 END IF;
 v_root:=atlas.company_work_native_ledger_owner_self_v1(
     v_farm.organization_id,p_ledger_id);
 IF v_root IS NULL OR v_root IS DISTINCT FROM atlas.current_person_id_v1()
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farm_crop_ledger_custody_v1 c
      JOIN atlas.ledger_organization_participations lop
        ON lop.ledger_id=c.ledger_id
       AND lop.organization_id=v_farm.organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      WHERE c.farm_id=v_farm.id
        AND c.ledger_id=p_ledger_id
        AND c.custody_state='active' AND c.ended_at IS NULL
    )
 THEN RAISE EXCEPTION
  'Current signed governing farm Ledger root and true native custody required'
  USING ERRCODE='42501';
 END IF;

 -- Journal events are candidate ATTENTION, never permission to act.
 -- Before exposing an item, recheck current original source condition.
 -- A genuine already-issued owner directive means that Harvest decision
 -- is no longer pending. Resolved/untrusted seed counts do NOT need a
 -- fabricated new purchase Work or lingering shortfall alert.
 WITH candidates AS (
   SELECT j.id,j.source_kind,j.source_id,j.event_key,j.created_at,
          j.occurred_at,j.journal_date,
          coalesce(d.decision,'pending_owner_decision') current_decision,
          d.id latest_source_decision_id,
          d.recorded_at latest_source_decision_at,
          coalesce(d.applies_to_current_evidence,false)
             latest_decision_applies_to_current_evidence,
          CASE
           WHEN j.source_kind='flower_harvest_batch'
             THEN 'harvest_preparation_owner_direction'
           WHEN j.source_kind='seed_lot'
             THEN 'verified_seed_shortfall_owner_direction'
          END AS decision_kind,
          CASE
           WHEN j.source_kind='flower_harvest_batch'
             THEN (
               SELECT count(*)::integer
               FROM atlas.flower_harvest_bucket_observations h
               WHERE h.batch_id=j.source_id AND h.farm_id=v_farm.id)
           ELSE NULL
          END AS observed_bucket_count,
          CASE
           WHEN j.source_kind='seed_lot'
             THEN (
               SELECT greatest(
                 coalesce((
                   SELECT sum(c.outstanding_quantity)
                   FROM atlas.seed_allocation_coverage_v1 c
                   WHERE c.seed_lot_id=p.seed_lot_id),0)-
                 coalesce(p.projected_on_hand_quantity,0),0)
               FROM atlas.seed_inventory_position_v1 p
               WHERE p.seed_lot_id=j.source_id AND p.count_trusted)
           ELSE NULL
          END AS current_verified_shortfall
   FROM atlas.journal_event_index j
   LEFT JOIN LATERAL (
     SELECT e.id,e.recorded_at,
            e.source_evidence_event_recorded_at=j.occurred_at
               AS applies_to_current_evidence,
            CASE WHEN e.source_evidence_event_recorded_at=j.occurred_at
                 THEN e.decision ELSE NULL END AS decision
     FROM atlas.uni_ops_p3_owner_attention_decision_events_v1 e
     WHERE e.attention_id=j.id
       AND e.ledger_id=p_ledger_id
       -- Keep the true latest decision as the required CAS predecessor
       -- EVEN WHEN a new physical event reopens currently pending review.
       -- Only its present-source validity affects the display state.
     ORDER BY e.recorded_at DESC,e.id DESC
     LIMIT 1
   ) d ON TRUE
   WHERE j.farm_id=v_farm.id
     AND j.organization_id=v_farm.organization_id
     AND j.event_kind='owner_decision'
     AND j.visibility_scope='owner'
     AND j.importance='attention'
     AND j.journal_date BETWEEN p_from_date AND p_through_date
     AND (
       (j.source_kind='flower_harvest_batch'
          AND (j.event_key LIKE 'weekly-harvest-owner-direction-pending:%'
            OR j.event_key LIKE 'harvest-preparation-needs-owner-direction:%')
          AND EXISTS(
            SELECT 1 FROM atlas.flower_harvest_batches b
            WHERE b.id=j.source_id AND b.farm_id=v_farm.id)
          AND NOT EXISTS(
            SELECT 1 FROM atlas.flower_preparation_directives d
            WHERE d.farm_id=v_farm.id AND d.harvest_batch_id=j.source_id)
       )
       OR
       (j.source_kind='seed_lot'
          AND j.event_key LIKE 'seed-shortfall-needs-owner-decision:%'
          AND EXISTS(
            SELECT 1 FROM atlas.seed_lots l
            WHERE l.id=j.source_id AND l.farm_id=v_farm.id
              AND l.status<>'retired')
          AND EXISTS(
            SELECT 1 FROM atlas.seed_inventory_position_v1 p
            WHERE p.seed_lot_id=j.source_id
              AND p.farm_id=v_farm.id AND p.count_trusted)
       )
     )
 ), still_pending AS (
   SELECT * FROM candidates c
   WHERE c.current_decision<>'decline_new_work_at_present'
     AND (c.source_kind='flower_harvest_batch'
      OR (c.source_kind='seed_lot'
          AND coalesce(c.current_verified_shortfall,0)>0))
 ), bounded AS (
   SELECT p.*,pg_catalog.row_number() OVER(
      ORDER BY p.created_at DESC,p.id DESC) AS pos
   FROM (
     SELECT * FROM still_pending
     ORDER BY created_at DESC,id DESC
     LIMIT 26
   ) p
 )
 SELECT coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'attentionId',id,
      'decisionKind',decision_kind,
      'sourceKind',source_kind,'sourceId',source_id,
      'evidenceOccurredAt',occurred_at,
      'attentionCreatedAt',created_at,
      'sourceJournalDate',journal_date,
      'harvestObservationCount',observed_bucket_count,
      'currentVerifiedSeedShortfall',current_verified_shortfall,
      'latestOwnerDecisionId',latest_source_decision_id,
      'latestOwnerDecisionAt',latest_source_decision_at,
      'latestOwnerDecisionAppliesToCurrentEvidence',
          latest_decision_applies_to_current_evidence,
      'expectedPreviousDecisionIdForNextChoice',latest_source_decision_id,
      'currentOwnerDecisionState',current_decision,
      'ownerDecisionStillRequired',
         current_decision='pending_owner_decision',
      'independentWorkAdmissionRequested',
         current_decision='request_independent_work_admission',
      'newPhysicalObservationNeeded',
         current_decision='hold_for_new_observation',
      'workAlreadyAuthorizedByAttention',false,
      'workerAlreadyAssignedByAttention',false,
      'clockAdmissionGranted',false,
      'operationalOwnerAttentionOnly',true,
      'principalEscalationQualified',false,
      'universalCompanyDecisionCreated',false
    ) ORDER BY created_at DESC,id DESC)
    FILTER(WHERE pos<=25),'[]'::jsonb),
    coalesce(pg_catalog.bool_or(pos>25),false)
 INTO v_items,v_has_more FROM bounded;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,
  'contractVersion','uni_ops_p3_owner_source_attention_v1',
  'farmId',v_farm.id,'governingLedgerId',p_ledger_id,
  'fromDate',p_from_date,'throughDate',p_through_date,
  'items',v_items,'hasMore',v_has_more,
  'onlyCurrentRealSourceConsidered',true,
  'newWorkCreated',false,
  'ownerAuthorityToIssueWorkInferred',false,
  'independentU2AcceptedFirstWorkStillRequired',true);
END;
$read$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(
 uuid,uuid,date,date) FROM PUBLIC,anon,authenticated,service_role;
