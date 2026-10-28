BEGIN;
-- Gate 0 preservation + Gate 1 private SHADOW ONLY. No Done API.
SET LOCAL statement_timeout='75s';
-- GATE 1: one eventual-authoritative Work lifecycle stream, installed SHADOW
-- ONLY. It never marks Work Done and grants no browser/API authority.
-- Existing original Work / Result / Acceptance rows are not modified.
-- Source events contain pointers, not ungoverned result payloads.
CREATE TABLE atlas.work_lifecycle_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 organization_id uuid,
 household_id uuid,
 sequence_no bigint NOT NULL CHECK (sequence_no>0),
 event_kind text NOT NULL CHECK(event_kind IN (
  'historical_state_snapshot','work_established','work_state_observed',
  'result_reported','result_accepted','responsibility_observed',
  'plan_event_observed'
 )),
 from_state text,
 to_state text,
 actor_user_id uuid,
 actor_attribution text NOT NULL CHECK(actor_attribution IN (
   'source_reporter_field','session_claim_only','unattributed'
 )),
 source_table text NOT NULL CHECK(source_table IN (
   'atlas.work_items','atlas.work_execution_results',
   'atlas.work_result_acceptances','atlas.work_allocations',
   'atlas.work_execution_plan_events'
 )),
 source_row_id uuid NOT NULL,
 source_idempotency_key text,
 provenance_kind text NOT NULL CHECK(provenance_kind IN (
  'historical_snapshot','observed_original_change','linked_original_evidence'
 )),
 occurred_at timestamptz,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 evidence_refs jsonb NOT NULL DEFAULT '{}'::jsonb,
 CONSTRAINT work_lifecycle_event_single_custody_v1
   CHECK ((organization_id IS NULL) <> (household_id IS NULL)),
 CONSTRAINT work_lifecycle_event_state_shape_v1 CHECK(
   (event_kind IN ('historical_state_snapshot','work_established','work_state_observed'))
    = (to_state IS NOT NULL)),
 CONSTRAINT work_lifecycle_event_sequence_v1 UNIQUE(work_item_id,sequence_no),
 CONSTRAINT work_lifecycle_event_evidence_object_v1 CHECK (
   jsonb_typeof(evidence_refs)='object'
 )
);
-- A mutable Work can legitimately change state multiple times; immutable
-- original Result, Acceptance and Plan records each produce one linked event.
CREATE UNIQUE INDEX work_lifecycle_original_evidence_once_v1
 ON atlas.work_lifecycle_events_v1(source_table,source_row_id,event_kind)
 WHERE event_kind IN (
   'historical_state_snapshot','result_reported',
   'result_accepted','plan_event_observed'
 );
CREATE INDEX work_lifecycle_work_order_v1
 ON atlas.work_lifecycle_events_v1(work_item_id,sequence_no DESC);
CREATE INDEX work_lifecycle_custody_order_v1
 ON atlas.work_lifecycle_events_v1(organization_id,recorded_at DESC,id)
 WHERE organization_id IS NOT NULL;

ALTER TABLE atlas.work_lifecycle_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.work_lifecycle_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.work_lifecycle_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.guard_work_lifecycle_event_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
 RAISE EXCEPTION 'Work lifecycle event history is immutable'
  USING ERRCODE='42501';
END;
$guard$;
REVOKE ALL ON FUNCTION atlas.guard_work_lifecycle_event_immutable_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER work_lifecycle_event_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.work_lifecycle_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_work_lifecycle_event_immutable_v1();
CREATE TRIGGER work_lifecycle_event_no_truncate_v1
 BEFORE TRUNCATE ON atlas.work_lifecycle_events_v1
 FOR EACH STATEMENT EXECUTE FUNCTION atlas.guard_work_lifecycle_event_immutable_v1();

-- Internal shadow capture. This is NOT a new Done API, accepts no
-- authority claims and cannot change Work, allocations, or physical Actuals.
-- Row custody is copied from the original Work, never chosen by the caller.
CREATE OR REPLACE FUNCTION atlas.append_work_lifecycle_observation_internal_v1(
 p_work_item_id uuid,
 p_event_kind text,
 p_source_table text,
 p_source_row_id uuid,
 p_from_state text DEFAULT NULL,
 p_to_state text DEFAULT NULL,
 p_actor_user_id uuid DEFAULT NULL,
 p_actor_attribution text DEFAULT 'unattributed',
 p_provenance_kind text DEFAULT 'observed_original_change',
 p_occurred_at timestamptz DEFAULT NULL,
 p_source_idempotency_key text DEFAULT NULL,
 p_evidence_refs jsonb DEFAULT '{}'::jsonb
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $append$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_id uuid;
 v_sequence bigint;
BEGIN
 IF p_work_item_id IS NULL OR p_source_row_id IS NULL
  OR p_event_kind NOT IN (
   'historical_state_snapshot','work_established','work_state_observed',
   'result_reported','result_accepted','responsibility_observed',
   'plan_event_observed')
  OR p_source_table NOT IN (
   'atlas.work_items','atlas.work_execution_results',
   'atlas.work_result_acceptances','atlas.work_allocations',
   'atlas.work_execution_plan_events')
  OR p_actor_attribution NOT IN (
   'source_reporter_field','session_claim_only','unattributed')
  OR p_provenance_kind NOT IN (
   'historical_snapshot','observed_original_change',
   'linked_original_evidence')
  OR p_evidence_refs IS NULL OR jsonb_typeof(p_evidence_refs)<>'object'
  OR (p_event_kind IN (
   'historical_state_snapshot','work_established','work_state_observed'))
   IS DISTINCT FROM (p_to_state IS NOT NULL)
 THEN RAISE EXCEPTION 'Invalid internal lifecycle observation shape'
  USING ERRCODE='22023'; END IF;
 -- Per-Work serial custody. This lock also makes duplicate historical
 -- import and original-evidence event links idempotent under concurrency.
 PERFORM pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(
   'atlas.work_lifecycle_events_v1:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id;
 IF v_work.id IS NULL OR
    (v_work.organization_id IS NULL)=(v_work.household_id IS NULL)
 THEN RAISE EXCEPTION 'Existing single-custody original Work required'
   USING ERRCODE='23514'; END IF;
 IF p_provenance_kind='historical_snapshot' OR
    p_event_kind IN ('historical_state_snapshot','result_reported',
    'result_accepted','plan_event_observed') THEN
   SELECT id INTO v_id FROM atlas.work_lifecycle_events_v1 e
   WHERE e.source_table=p_source_table
     AND e.source_row_id=p_source_row_id
     AND e.event_kind=p_event_kind;
   IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 END IF;
 SELECT coalesce(max(e.sequence_no),0)+1 INTO v_sequence
 FROM atlas.work_lifecycle_events_v1 e WHERE e.work_item_id=p_work_item_id;
 INSERT INTO atlas.work_lifecycle_events_v1(
  work_item_id,organization_id,household_id,sequence_no,
  event_kind,from_state,to_state,actor_user_id,actor_attribution,
  source_table,source_row_id,source_idempotency_key,provenance_kind,
  occurred_at,evidence_refs)
 VALUES (
  v_work.id,v_work.organization_id,v_work.household_id,v_sequence,
  p_event_kind,p_from_state,p_to_state,p_actor_user_id,
  p_actor_attribution,p_source_table,p_source_row_id,
  p_source_idempotency_key,p_provenance_kind,
  p_occurred_at,p_evidence_refs)
 RETURNING id INTO v_id;
 RETURN v_id;
END;
$append$;
REVOKE ALL ON FUNCTION atlas.append_work_lifecycle_observation_internal_v1(
 uuid,text,text,uuid,text,text,uuid,text,text,timestamptz,text,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

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

LOCK TABLE atlas.work_items,atlas.work_allocations,
 atlas.work_execution_results,atlas.work_result_acceptances,
 atlas.work_execution_plan_events IN SHARE ROW EXCLUSIVE MODE;
SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();
-- Shadow reads ONLY; this view must never be used as permission to
-- complete Work. It compares one chronological state observation stream
-- with the original mutable Work position for cutover parity.
CREATE OR REPLACE VIEW atlas.work_lifecycle_shadow_reconciliation_v1
WITH (security_invoker=true)
AS
SELECT
 w.id AS work_item_id,w.organization_id,w.household_id,
 w.work_state AS live_state,
 (SELECT e.to_state FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=w.id
     AND e.event_kind IN (
       'historical_state_snapshot','work_established','work_state_observed')
   ORDER BY e.sequence_no DESC LIMIT 1) AS shadow_state,
 w.work_state IS NOT DISTINCT FROM
 (SELECT e.to_state FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=w.id
     AND e.event_kind IN (
       'historical_state_snapshot','work_established','work_state_observed')
   ORDER BY e.sequence_no DESC LIMIT 1) AS state_matches,
 (SELECT count(*) FROM atlas.work_execution_results r
    WHERE r.work_item_id=w.id) AS original_result_count,
 (SELECT count(*) FROM atlas.work_result_acceptances a
    WHERE a.work_item_id=w.id AND a.decision='accepted')
      AS original_accepted_result_count,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='result_reported')
      AS shadow_result_links,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='result_accepted')
      AS shadow_acceptance_links,
 (SELECT count(*) FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=w.id AND e.event_kind='historical_state_snapshot')
      AS baseline_count
FROM atlas.work_items w;
REVOKE ALL ON atlas.work_lifecycle_shadow_reconciliation_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- These must be installed only after a baseline is seeded while originals
-- are locked in a single migration transaction.
CREATE TRIGGER work_items_shadow_lifecycle_insert_v1
 AFTER INSERT ON atlas.work_items FOR EACH ROW
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_items_shadow_lifecycle_state_v1
 AFTER UPDATE OF work_state ON atlas.work_items
 FOR EACH ROW WHEN(OLD.work_state IS DISTINCT FROM NEW.work_state)
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();

CREATE TRIGGER work_execution_results_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_result_acceptances_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_result_acceptances
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_allocations_shadow_lifecycle_insert_v1
 AFTER INSERT ON atlas.work_allocations
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_allocations_shadow_lifecycle_state_v1
 AFTER UPDATE OF state,assignee_canonical_person_id,
 assignee_membership_id,assignee_household_member_id
 ON atlas.work_allocations FOR EACH ROW
 EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();
CREATE TRIGGER work_execution_plan_events_shadow_lifecycle_v1
 AFTER INSERT ON atlas.work_execution_plan_events
 FOR EACH ROW EXECUTE FUNCTION atlas.observe_original_work_lifecycle_shadow_v1();

COMMIT;
