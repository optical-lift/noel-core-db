-- Gate 0 preservation. A baseline states "Atlas had this state when
-- observed"; it is NOT evidence of a historical signed completion.
CREATE UNIQUE INDEX work_lifecycle_historical_origin_once_v1
 ON atlas.work_lifecycle_events_v1(source_table,source_row_id,event_kind)
 WHERE provenance_kind='historical_snapshot'
   AND event_kind<>'historical_state_snapshot';

CREATE OR REPLACE FUNCTION atlas.seed_work_lifecycle_shadow_baseline_internal_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $seed$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_accept atlas.work_result_acceptances%ROWTYPE;
 v_allocation atlas.work_allocations%ROWTYPE;
 v_plan atlas.work_execution_plan_events%ROWTYPE;
 v_works integer:=0;
 v_results integer:=0;
 v_acceptances integer:=0;
 v_allocations integer:=0;
 v_plan_events integer:=0;
BEGIN
 -- Not a user-facing writer. It cannot be used as an alternate Done.
 IF auth.uid() IS NOT NULL THEN
   RAISE EXCEPTION 'Historical baseline is a privileged custody operation'
    USING ERRCODE='42501';
 END IF;
 -- Release assembly locks originals before this call and trigger creation,
 -- so no live Work can change between snapshot and starting shadow capture.
 FOR v_work IN SELECT w.* FROM atlas.work_items w
  WHERE NOT EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id)
  ORDER BY w.id LOOP
  PERFORM atlas.append_work_lifecycle_observation_internal_v1(
    v_work.id,'historical_state_snapshot','atlas.work_items',v_work.id,
    NULL,v_work.work_state,NULL,'unattributed','historical_snapshot',NULL,NULL,
    jsonb_build_object(
      'originalWorkCreatedAt',v_work.created_at,
      'originalWorkCompletedAt',v_work.completed_at,
      'originalWorkCancelledAt',v_work.cancelled_at,
      'originalSourceType',v_work.source_object_type,
      'originalSourceId',v_work.source_object_id,
      'acceptedCompletionEvidenceExists',EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
        WHERE a.work_item_id=v_work.id AND a.decision='accepted'
          AND r.result_kind='completed' AND r.work_item_id=v_work.id)
    )
  );
  v_works:=v_works+1;
 END LOOP;

 -- Original evidence is linked, not duplicated, interpreted or re-signed.
 FOR v_result IN SELECT * FROM atlas.work_execution_results
   ORDER BY reported_at,id LOOP
   PERFORM atlas.append_work_lifecycle_observation_internal_v1(
    v_result.work_item_id,'result_reported',
    'atlas.work_execution_results',v_result.id,
    NULL,NULL,v_result.reported_by_user_id,
    CASE WHEN v_result.reported_by_user_id IS NULL THEN 'unattributed'
      ELSE 'source_reporter_field' END,
    'linked_original_evidence',v_result.reported_at,
    v_result.idempotency_key,
    jsonb_build_object('resultId',v_result.id,
      'resultKind',v_result.result_kind,
      'resultContractKey',v_result.result_contract_key,
      'responsibleAllocationId',v_result.responsible_allocation_id)
   );
   v_results:=v_results+1;
 END LOOP;
 FOR v_accept IN SELECT * FROM atlas.work_result_acceptances
   ORDER BY accepted_at,id LOOP
   PERFORM atlas.append_work_lifecycle_observation_internal_v1(
    v_accept.work_item_id,'result_accepted',
    'atlas.work_result_acceptances',v_accept.id,
    NULL,NULL,NULL,'unattributed','linked_original_evidence',
    v_accept.accepted_at,NULL,
    jsonb_build_object('acceptanceId',v_accept.id,
      'executionResultId',v_accept.execution_result_id,
      'decision',v_accept.decision,
      'acceptanceKind',v_accept.acceptance_kind)
   );
   v_acceptances:=v_acceptances+1;
 END LOOP;
 -- An older allocation's currently observed state is not a proof of
 -- all previous assignment/transfer events. No invented personnel actor.
 FOR v_allocation IN SELECT * FROM atlas.work_allocations
  ORDER BY created_at,id LOOP
  PERFORM atlas.append_work_lifecycle_observation_internal_v1(
   v_allocation.work_item_id,'responsibility_observed',
   'atlas.work_allocations',v_allocation.id,
   NULL,NULL,NULL,'unattributed','historical_snapshot',NULL,NULL,
   jsonb_build_object('allocationId',v_allocation.id,
    'observedAllocationState',v_allocation.state,
    'allocationRole',v_allocation.allocation_role,
    'sourceRecordedAllocatedAt',v_allocation.allocated_at,
    'sourceRecordedCompletedAt',v_allocation.completed_at,
    'basisKind',v_allocation.establishment_basis_kind)
  );
  v_allocations:=v_allocations+1;
 END LOOP;
 FOR v_plan IN SELECT * FROM atlas.work_execution_plan_events
   ORDER BY created_at,id LOOP
   PERFORM atlas.append_work_lifecycle_observation_internal_v1(
    v_plan.work_item_id,'plan_event_observed',
    'atlas.work_execution_plan_events',v_plan.id,
    NULL,NULL,NULL,'unattributed','linked_original_evidence',
    v_plan.created_at,NULL,
    jsonb_build_object('originalPlanEventId',v_plan.id,
      'planId',v_plan.plan_id,'originalPlanEventKind',v_plan.event_kind)
   );
   v_plan_events:=v_plan_events+1;
 END LOOP;
 RETURN jsonb_build_object(
  'contract','work_lifecycle_shadow_baseline_v1',
  'historicalWorksInspected',v_works,
  'originalResultsLinked',v_results,
  'originalAcceptancesLinked',v_acceptances,
  'originalAllocationStatesInspected',v_allocations,
  'originalPlanEventsLinked',v_plan_events,
  'madeNoWorkStateChanges',true,'madeNoNewResultAcceptances',true);
END;
$seed$;
REVOKE ALL ON FUNCTION atlas.seed_work_lifecycle_shadow_baseline_internal_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- The one shadow observer receives existing source changes only. It DOES NOT
-- authorize completion, does not alter Work and is NOT a completion contract.
CREATE OR REPLACE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $capture$
DECLARE
 v_work_id uuid;
 v_evidence jsonb;
 v_event_kind text;
 v_from text;
 v_to text;
 v_actor uuid;
 v_actor_basis text:='unattributed';
 v_occurred timestamptz;
 v_action_key text;
BEGIN
 IF TG_TABLE_SCHEMA<>'atlas' OR TG_LEVEL<>'ROW' THEN
  RAISE EXCEPTION 'Invalid lifecycle source context' USING ERRCODE='42501';
 END IF;
 IF TG_TABLE_NAME='work_items' THEN
   IF TG_OP='UPDATE' AND NEW.work_state IS NOT DISTINCT FROM OLD.work_state
   THEN RETURN NEW; END IF;
   -- When the one authoritative transition has already been appended in
   -- this same locked transaction, the subsequent mutable Work projection
   -- MUST NOT be mistaken for a second lifecycle transition event.
   IF TG_OP='UPDATE' AND EXISTS(
     SELECT 1 FROM atlas.work_lifecycle_events_v1 e
     WHERE e.id=(
       SELECT last.id FROM atlas.work_lifecycle_events_v1 last
       WHERE last.work_item_id=NEW.id
       ORDER BY last.sequence_no DESC LIMIT 1)
       AND e.event_kind='work_transition_applied'
       AND e.provenance_kind='authoritative_transition'
       AND e.from_state=OLD.work_state
       AND e.to_state=NEW.work_state
       AND e.occurred_at IS NOT DISTINCT FROM
         CASE WHEN NEW.work_state='completed' THEN NEW.completed_at
          WHEN NEW.work_state='cancelled' THEN NEW.cancelled_at
          ELSE NULL END
   ) THEN RETURN NEW; END IF;
   v_work_id:=NEW.id;
   v_event_kind:=CASE WHEN TG_OP='INSERT' THEN 'work_established'
     ELSE 'work_state_observed' END;
   v_to:=NEW.work_state;
   IF TG_OP='UPDATE' THEN v_from:=OLD.work_state; END IF;
   v_actor:=auth.uid();
   IF v_actor IS NOT NULL THEN v_actor_basis:='session_claim_only'; END IF;
   v_occurred:=CASE WHEN NEW.work_state='completed' THEN NEW.completed_at
      WHEN NEW.work_state='cancelled' THEN NEW.cancelled_at
      ELSE NULL END;
   v_evidence:=jsonb_build_object(
      'originalWorkId',NEW.id,
      'workStatusRecordedAt',NEW.updated_at,
      'sourceRecordedCompletedAt',NEW.completed_at,
      'sourceRecordedCancelledAt',NEW.cancelled_at);
 ELSIF TG_TABLE_NAME='work_execution_results' AND TG_OP='INSERT' THEN
   v_work_id:=NEW.work_item_id;v_event_kind:='result_reported';
   v_actor:=NEW.reported_by_user_id;
   IF v_actor IS NOT NULL THEN v_actor_basis:='source_reporter_field'; END IF;
   v_occurred:=NEW.reported_at;v_action_key:=NEW.idempotency_key;
   v_evidence:=jsonb_build_object('resultId',NEW.id,
     'resultKind',NEW.result_kind,
     'resultContractKey',NEW.result_contract_key,
     'responsibleAllocationId',NEW.responsible_allocation_id);
 ELSIF TG_TABLE_NAME='work_result_acceptances' AND TG_OP='INSERT' THEN
   v_work_id:=NEW.work_item_id;v_event_kind:='result_accepted';
   v_occurred:=NEW.accepted_at;
   v_evidence:=jsonb_build_object('acceptanceId',NEW.id,
    'executionResultId',NEW.execution_result_id,
    'decision',NEW.decision,'acceptanceKind',NEW.acceptance_kind);
 ELSIF TG_TABLE_NAME='work_allocations' THEN
   IF TG_OP='UPDATE' AND
      NEW.state IS NOT DISTINCT FROM OLD.state AND
      NEW.assignee_canonical_person_id IS NOT DISTINCT FROM OLD.assignee_canonical_person_id AND
      NEW.assignee_membership_id IS NOT DISTINCT FROM OLD.assignee_membership_id AND
      NEW.assignee_household_member_id IS NOT DISTINCT FROM OLD.assignee_household_member_id
   THEN RETURN NEW; END IF;
   v_work_id:=NEW.work_item_id;v_event_kind:='responsibility_observed';
   v_actor:=auth.uid();
   IF v_actor IS NOT NULL THEN v_actor_basis:='session_claim_only'; END IF;
   v_evidence:=jsonb_build_object('allocationId',NEW.id,
    'currentAllocationState',NEW.state,'allocationRole',NEW.allocation_role,
    'basisKind',NEW.establishment_basis_kind);
 ELSIF TG_TABLE_NAME='work_execution_plan_events' AND TG_OP='INSERT' THEN
   v_work_id:=NEW.work_item_id;v_event_kind:='plan_event_observed';
   v_occurred:=NEW.created_at;
   v_evidence:=jsonb_build_object('originalPlanEventId',NEW.id,
    'planId',NEW.plan_id,'originalPlanEventKind',NEW.event_kind);
 ELSE
   RAISE EXCEPTION 'Unsupported original Work lifecycle source event'
    USING ERRCODE='42501';
 END IF;
 PERFORM atlas.append_work_lifecycle_observation_internal_v1(
   v_work_id,v_event_kind,
   'atlas.'||TG_TABLE_NAME,NEW.id,
   v_from,v_to,v_actor,v_actor_basis,
   CASE WHEN TG_TABLE_NAME='work_items' OR TG_TABLE_NAME='work_allocations'
     THEN 'observed_original_change' ELSE 'linked_original_evidence' END,
   v_occurred,v_action_key,v_evidence);
 RETURN NEW;
END;
$capture$;
REVOKE ALL ON FUNCTION atlas.observe_original_work_lifecycle_shadow_v1()
 FROM PUBLIC,anon,authenticated,service_role;
