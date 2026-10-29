BEGIN;
-- CLONE TEST ONLY: this candidate is NEVER production-releasable.
-- Refuse absent synthetic C1 canary before executing candidate DDL.
DO $only_disposable$
BEGIN
 IF current_database()<>'postgres'
 OR (SELECT count(*) FROM auth.users WHERE
   id='e5200000-0000-4000-8000-000000000001'::uuid)<>1
 OR (SELECT count(*) FROM atlas.growing_objects WHERE
   id='e5200000-0000-4000-8000-000000000b03'::uuid)<>1
 THEN
  RAISE EXCEPTION 'Test-only care source requires an exact fictional C1 clone';
 END IF;
END;
$only_disposable$;

-- EXISTING CANONICAL ORIGINAL WORK is provided by production-schema clone.
-- Never replay older original Work DDL into a production-shaped test.
-- EXACT ONE LIFECYCLE SHADOW
-- Gate 0 preservation and Gate 1 private SHADOW ONLY.
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
       'historical_state_snapshot','work_established','work_state_observed',
       'work_transition_applied')
   ORDER BY e.sequence_no DESC LIMIT 1) AS shadow_state,
 w.work_state IS NOT DISTINCT FROM
 (SELECT e.to_state FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=w.id
     AND e.event_kind IN (
       'historical_state_snapshot','work_established','work_state_observed',
       'work_transition_applied')
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


-- EXACT SINGLE DONE AUTHORITY
-- GATE 2 PREVIEW ONLY. Not an independent Done API. This is the
-- eventual single lifecycle transition authority. No client EXECUTE, no
-- production release, and no old writer delegation until signed acceptance.
-- Admits signed responsible-Person attestation and evidence-grounded
-- governor witness for ordinary Work through THIS SAME authority. Witness
-- is an owner's recorded CLAIM about someone else's performance.
-- Management, farm, household, communications and production remain closed.
-- Event shared-checklist state confirmation is admitted ONLY with existing
-- signed Ledger/Occurrence identity and explicit non-performance evidence.

ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_event_kind_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_event_kind_check CHECK(event_kind IN(
 'historical_state_snapshot','work_established','work_state_observed',
 'result_reported','result_accepted','responsibility_observed',
 'plan_event_observed','work_transition_applied'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_actor_attribution_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_actor_attribution_check CHECK(
 actor_attribution IN ('source_reporter_field','session_claim_only',
 'unattributed','verified_signed_transition'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_provenance_kind_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_provenance_kind_check CHECK(
 provenance_kind IN ('historical_snapshot','observed_original_change',
 'linked_original_evidence','authoritative_transition'));
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_event_state_shape_v1;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_event_state_shape_v1 CHECK(
 (event_kind IN ('historical_state_snapshot','work_established',
   'work_state_observed','work_transition_applied'))=(to_state IS NOT NULL));
CREATE UNIQUE INDEX work_lifecycle_one_transition_action_v1
 ON atlas.work_lifecycle_events_v1(work_item_id,source_idempotency_key)
 WHERE event_kind='work_transition_applied';

CREATE OR REPLACE FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(
 p_work_item_id uuid,p_transition_kind text,p_result_id uuid,
 p_idempotency_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $transition$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_result atlas.work_execution_results%ROWTYPE;
 v_accept atlas.work_result_acceptances%ROWTYPE;
 v_allocation atlas.work_allocations%ROWTYPE;
 v_event atlas.work_lifecycle_events_v1%ROWTYPE;
 v_actor uuid:=atlas.current_person_id_v1();
 v_uid uuid:=auth.uid();
 v_native_ledger uuid;
 v_report_mode text;
 v_witnessed boolean:=false;
 v_shared_event boolean:=false;
 v_physical_care boolean:=false;
 v_occurrence_id uuid;
 v_claimed_performer uuid;
 v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
 v_completed_at timestamptz;
 v_sequence bigint;
BEGIN
 IF v_uid IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
   OR p_result_id IS NULL OR v_key IS NULL OR length(v_key)>160
   OR p_transition_kind IS DISTINCT FROM 'complete' THEN
   RAISE EXCEPTION 'Exact signed original Work transition, evidence and action required'
    USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(
     'atlas.work_lifecycle_events_v1:'||p_work_item_id::text,0));
 -- Serial original Work custody. A source trigger cannot independently
 -- establish a second authoritative event in this transaction.
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL THEN
   RAISE EXCEPTION 'This authority slice requires original Organization Work'
    USING ERRCODE='42501';
 END IF;
 v_shared_event:=(v_work.source_object_type='ledger_occurrence_shared_work'
   AND v_work.result_contract_key='ledger_occurrence_shared_confirmation_v1');
 v_physical_care:=(v_work.source_object_type='rhythm_state'
   AND v_work.result_contract_key='continuing_care_actual_v1');
 SELECT * INTO v_result FROM atlas.work_execution_results r
 WHERE r.id=p_result_id AND r.work_item_id=v_work.id
   AND r.organization_id=v_work.organization_id
   AND r.household_id IS NULL
   AND r.result_kind='completed'
   AND r.result_contract_key IN (
     'ordinary_company_work_worker_attestation_v1',
     'ledger_occurrence_shared_confirmation_v1',
     'continuing_care_actual_v1')
   AND r.reported_by_user_id=v_uid
   AND r.idempotency_key=v_key;
 IF v_result.id IS NULL
   OR v_work.result_contract_key IS DISTINCT FROM v_result.result_contract_key
   OR (v_shared_event IS DISTINCT FROM
       (v_result.result_contract_key='ledger_occurrence_shared_confirmation_v1'))
   OR (v_physical_care IS DISTINCT FROM
       (v_result.result_contract_key='continuing_care_actual_v1'))
 THEN RAISE EXCEPTION 'Original signed Work Result missing or mismatched'
    USING ERRCODE='42501'; END IF;
 SELECT * INTO v_accept FROM atlas.work_result_acceptances a
 WHERE a.execution_result_id=v_result.id AND a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id AND a.household_id IS NULL
   AND a.decision='accepted';
 IF v_accept.id IS NULL THEN
   RAISE EXCEPTION 'Existing accepted source evidence required'
    USING ERRCODE='42501';
 END IF;
 IF v_shared_event THEN
   -- Shared checklist Done asserts a state, not who physically performed it.
   -- Its original result has NO responsible allocation by design.
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
      v_result.metadata->>'ledgerId');
   v_occurrence_id:=atlas.rhythm_safe_uuid_v1(
      v_result.metadata->>'occurrenceId');
   IF v_native_ledger IS NULL OR v_occurrence_id IS NULL
     OR v_work.source_object_id IS DISTINCT FROM v_occurrence_id
     OR v_work.metadata->>'ledgerId' IS DISTINCT FROM v_native_ledger::text
     OR v_work.metadata->>'sourceContract' IS DISTINCT FROM
       'ledger_occurrence_shared_work_v1'
     OR v_result.responsible_allocation_id IS NOT NULL
     OR v_result.metadata->>'source' IS DISTINCT FROM
       'mark_ledger_occurrence_shared_work_done_self_api_v1'
     OR v_result.metadata->>'actorPersonId' IS DISTINCT FROM v_actor::text
     OR v_result.metadata->>'notWorkerResult' IS DISTINCT FROM 'true'
     OR v_result.metadata->>'allocationNotRequired' IS DISTINCT FROM 'true'
     OR v_result.payload->>'stateAssertion' IS DISTINCT FROM
       'ordinary_shared_work_marked_done'
     OR v_result.payload->>'markedByPersonId' IS DISTINCT FROM v_actor::text
     OR v_result.payload->>'personalPerformanceNotClaimed' IS DISTINCT FROM 'true'
     OR v_result.payload->'performedByPersonId' IS DISTINCT FROM 'null'::jsonb
     OR v_accept.acceptance_kind IS DISTINCT FROM
       'shared_checklist_state_confirmation'
     OR v_accept.evidence->>'markedByPersonId' IS DISTINCT FROM v_actor::text
     OR v_accept.evidence->>'sourceActionId' IS DISTINCT FROM
       v_result.payload->>'sourceActionId'
     OR v_accept.evidence->>'physicalPerformerAsserted' IS DISTINCT FROM 'false'
     OR atlas.ledger_occurrence_shared_work_actor_self_v1(
       v_work.organization_id,v_native_ledger,v_occurrence_id)
         IS DISTINCT FROM v_actor
     OR NOT EXISTS (
       SELECT 1 FROM atlas.work_item_context_links ctx
       JOIN atlas.company_work_native_ledger_relevance rel
         ON rel.organization_id=ctx.organization_id
          AND rel.work_item_id=ctx.work_item_id
          AND rel.ledger_id=v_native_ledger
          AND rel.attribution_state='active'
       WHERE ctx.organization_id=v_work.organization_id
         AND ctx.work_item_id=v_work.id
         AND ctx.subject_domain='temporal'
         AND ctx.subject_kind='occurrence'
         AND ctx.subject_id=v_occurrence_id
         AND ctx.relation_kind='for'
     )
   THEN RAISE EXCEPTION 'Exact shared Event evidence or current Person disclosure unavailable'
      USING ERRCODE='42501'; END IF;
   v_claimed_performer:=NULL;
   v_witnessed:=false;
 ELSE

  -- Care can finish original Work only with an exact first-party physical
  -- Actual, observation, accepted result, and qualifying rhythm satisfaction.
  -- A checkbox or elapsed interval never manufactures this evidence.
  IF v_physical_care AND (
    v_accept.acceptance_kind IS DISTINCT FROM 'source_qualified_physical_actual'
    OR v_accept.accepted_by_domain IS DISTINCT FROM 'continuing_care_actual'
    OR v_result.metadata->>'authenticatedReporterPersonId' IS DISTINCT FROM v_actor::text
    OR NOT EXISTS(
      SELECT 1 FROM atlas.rhythm_state s
      JOIN atlas.care_result_events c
        ON c.id=atlas.rhythm_safe_uuid_v1(v_result.payload->>'careResultId')
        AND c.scope_kind='farm' AND c.scope_id=s.farm_id
        AND c.subject_domain='farm' AND c.subject_kind='growing_object'
        AND c.subject_id=s.subject_id::text
      JOIN atlas.care_observation_events o
        ON o.id=atlas.rhythm_safe_uuid_v1(v_result.payload->>'careObservationId')
        AND o.scope_kind=c.scope_kind AND o.scope_id=c.scope_id
        AND o.subject_domain=c.subject_domain AND o.subject_kind=c.subject_kind
        AND o.subject_id=c.subject_id
      JOIN atlas.rhythm_satisfactions sat
        ON sat.rhythm_state_id=s.id AND sat.organization_id=s.organization_id
        AND sat.farm_id=s.farm_id AND sat.source_kind='continuing_care_actual'
        AND sat.source_id=c.id AND sat.satisfaction_kind IN ('full','conditional')
      JOIN atlas.work_item_context_links ctx
        ON ctx.organization_id=v_work.organization_id AND ctx.work_item_id=v_work.id
        AND ctx.subject_domain='spatial' AND ctx.subject_kind='growing_object'
        AND ctx.subject_id=s.subject_id AND ctx.relation_kind='acts_on'
      WHERE s.id=v_work.source_object_id
        AND s.organization_id=v_work.organization_id
        AND s.subject_kind='growing_object'
        AND s.rhythm_key IN ('weed_stewardship','mowing')
        AND v_result.metadata->>'rhythmStateId'=s.id::text
        AND c.source_kind='continuing_care_actual'
        AND c.source_key=v_key AND c.actor_user_id=v_uid
        AND c.metadata->>'workItemId'=v_work.id::text
        AND c.metadata->>'rhythmStateId'=s.id::text
        AND c.metadata->>'physicalActualKind'=v_result.metadata->>'actualKind'
        AND o.source_kind='continuing_care_actual_observation'
        AND o.source_key='continuing-care-observation:'||c.id::text
        AND o.observed_by_user_id=v_uid
        AND o.metadata->>'workItemId'=v_work.id::text
        AND o.metadata->>'careResultId'=c.id::text
        AND c.condition_after=o.condition_state
        AND v_result.payload->>'conditionAfter'=c.condition_after
        AND v_result.payload->>'actualKind'=v_result.metadata->>'actualKind'
        AND v_accept.evidence->>'careResultId'=c.id::text
        AND v_accept.evidence->>'careObservationId'=o.id::text
        AND v_accept.evidence->>'actualKind'=v_result.metadata->>'actualKind'
        AND v_accept.evidence->>'sourceRuleId'=sat.rhythm_rule_id::text
        AND v_accept.evidence->>'actualReporter'=v_actor::text
        AND sat.source_event=v_result.metadata->>'actualKind'
        AND sat.created_by_user_id=v_uid
        AND sat.evidence->>'workItemId'=v_work.id::text
        AND sat.evidence->>'careResultId'=c.id::text
        AND sat.evidence->>'workResultId'=v_result.id::text
    )
  ) THEN
    RAISE EXCEPTION 'Exact qualifying physical Actual and rhythm satisfaction required'
      USING ERRCODE='42501';
  END IF;
 v_report_mode:=coalesce(v_result.metadata->>'reportMode','own_work');
 v_witnessed:=v_report_mode='owner_witness';
 IF (v_witnessed AND (
       v_accept.acceptance_kind IS DISTINCT FROM 'owner_witnessed_person_result'
       OR v_result.metadata->>'performanceIsWitnessedClaim' IS DISTINCT FROM 'true'
       OR v_result.metadata->>'authenticatedReporterPersonId' IS DISTINCT FROM v_actor::text
       OR length(btrim(coalesce(v_result.payload->>'ownerWitnessEvidence',''))) NOT BETWEEN 16 AND 2000
       OR v_accept.evidence->>'ownerWitnessEvidence' IS DISTINCT FROM
         v_result.payload->>'ownerWitnessEvidence'))
   OR (NOT v_witnessed AND (
       v_report_mode<>'own_work'
       OR (v_physical_care AND v_accept.acceptance_kind IS DISTINCT FROM
             'source_qualified_physical_actual')
       OR (NOT v_physical_care AND v_accept.acceptance_kind NOT IN (
         'self_responsible_person_attestation','delegated_worker_attestation'))
       OR (v_result.metadata ? 'authenticatedReporterPersonId'
         AND v_result.metadata->>'authenticatedReporterPersonId'
              IS DISTINCT FROM v_actor::text)))
 THEN RAISE EXCEPTION 'Accepted evidence mode or reporter attribution mismatch'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.id=v_result.responsible_allocation_id
   AND a.work_item_id=v_work.id
   AND a.organization_id=v_work.organization_id
   AND a.household_id IS NULL
   AND a.allocation_role='responsible'
   AND a.state IN ('active','completed');
 IF v_allocation.id IS NULL THEN
   RAISE EXCEPTION 'Current original responsibility unavailable'
     USING ERRCODE='42501'; END IF;
 v_claimed_performer:=v_allocation.assignee_canonical_person_id;
 IF v_witnessed THEN
   -- Original accountable person is NOT the one clicking Done.
   -- The owner's evidence must point to that SAME responsible Person.
   IF v_claimed_performer IS NULL OR v_claimed_performer=v_actor
     OR v_result.metadata->>'source' IS DISTINCT FROM
       'report_connected_person_company_work_internal_v1'
     OR v_result.metadata->>'canonicalResponsiblePersonId'
       IS DISTINCT FROM v_claimed_performer::text
     OR v_accept.evidence->>'canonicalResponsiblePersonId'
       IS DISTINCT FROM v_claimed_performer::text
     OR v_accept.evidence->>'responsibleAllocationId'
       IS DISTINCT FROM v_allocation.id::text
     OR v_accept.evidence->>'authenticatedReporterPersonId'
       IS DISTINCT FROM v_actor::text
     OR v_allocation.establishment_basis_kind NOT IN(
       'person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
     )
   THEN RAISE EXCEPTION 'Witness claim does not match responsible Person provenance'
       USING ERRCODE='42501'; END IF;
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
     v_allocation.establishment_basis->>'nativeLedgerId');
   IF v_native_ledger IS NULL OR
     atlas.company_work_native_ledger_owner_self_v1(
       v_work.organization_id,v_native_ledger) IS DISTINCT FROM v_actor
   THEN RAISE EXCEPTION 'Present native Ledger root authority required for witness'
       USING ERRCODE='42501'; END IF;
 ELSIF v_allocation.assignee_canonical_person_id IS DISTINCT FROM v_actor THEN
   -- Existing self-adopted original Work is membership-backed.
   IF NOT (v_allocation.establishment_basis_kind='self_adoption'
      AND EXISTS(SELECT 1 FROM atlas.organization_memberships m
        WHERE m.id=v_allocation.assignee_membership_id
          AND m.organization_id=v_work.organization_id
          AND m.person_id=v_actor AND m.user_id=v_uid AND m.active))
   THEN RAISE EXCEPTION 'Caller is not the responsible Person'
     USING ERRCODE='42501'; END IF;
   -- Self-adopted Work holds the responsible Person through the original
   -- organization membership, not the connection-assignee field.
   v_claimed_performer:=v_actor;
 ELSIF v_allocation.establishment_basis_kind IN (
    'person_connection_receiver_uptake','delegated_under_standing_scope',
    'ledger_connection_direct_assignment','original_subject_direct_assignment_v1') THEN
   v_native_ledger:=atlas.rhythm_safe_uuid_v1(
     v_allocation.establishment_basis->>'nativeLedgerId');
   IF v_native_ledger IS NULL
     OR NOT atlas.person_original_work_identity_disclosed_self_v1(
       v_work.organization_id,v_native_ledger,v_work.id,v_actor) THEN
     RAISE EXCEPTION 'Original Work is no longer disclosed to the Person'
       USING ERRCODE='42501'; END IF;
 ELSE
   RAISE EXCEPTION 'Responsible source establishment not yet admitted'
     USING ERRCODE='42501';
 END IF;
 END IF;
 SELECT * INTO v_event FROM atlas.work_lifecycle_events_v1 e
 WHERE e.work_item_id=v_work.id
   AND e.event_kind='work_transition_applied'
   AND e.source_idempotency_key=v_key
 ORDER BY e.sequence_no DESC LIMIT 1;
 IF v_event.id IS NOT NULL THEN
   IF v_event.source_row_id IS DISTINCT FROM v_accept.id
     OR v_event.actor_user_id IS DISTINCT FROM v_uid
     OR v_event.from_state IS DISTINCT FROM 'open'
     OR v_event.to_state IS DISTINCT FROM 'completed'
     OR v_work.work_state IS DISTINCT FROM 'completed' THEN
     RAISE EXCEPTION 'Transition action identity conflicts with original evidence'
       USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('ok',true,
     'contractVersion','universal_work_lifecycle_transition_v1',
     'idempotent',true,'eventId',v_event.id,
     'workItemId',v_work.id,'workState','completed',
     'originalResultId',v_result.id,'acceptedEvidenceId',v_accept.id,
     'reporterPersonId',v_actor,'responsiblePersonId',v_claimed_performer,
     'performanceIsWitnessedClaim',v_witnessed,
     'personalPerformanceNotClaimed',v_shared_event,
     'recordedAt',v_event.recorded_at,'effectiveAt',v_event.occurred_at);
 END IF;
 IF v_work.work_state<>'open' OR v_work.completed_at IS NOT NULL THEN
   RAISE EXCEPTION 'Original Work is not currently open; no duplicate Done'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
   WHERE e.work_item_id=v_work.id
     AND e.event_kind='work_transition_applied'
     AND e.to_state='completed'
     AND e.from_state='open'
     AND e.source_row_id=v_accept.id)
 THEN RAISE EXCEPTION 'Accepted evidence already drove a lifecycle transition'
   USING ERRCODE='23505'; END IF;
 SELECT coalesce(max(e.sequence_no),0)+1 INTO v_sequence
 FROM atlas.work_lifecycle_events_v1 e WHERE e.work_item_id=v_work.id;
 v_completed_at:=clock_timestamp();
 INSERT INTO atlas.work_lifecycle_events_v1(
   work_item_id,organization_id,household_id,sequence_no,
   event_kind,from_state,to_state,actor_user_id,actor_attribution,
   source_table,source_row_id,source_idempotency_key,provenance_kind,
   occurred_at,evidence_refs)
 VALUES(v_work.id,v_work.organization_id,NULL,v_sequence,
   'work_transition_applied','open','completed',v_uid,
   'verified_signed_transition','atlas.work_result_acceptances',v_accept.id,
   v_key,'authoritative_transition',v_completed_at,
   jsonb_build_object('transitionKind','complete',
     'originalResultId',v_result.id,'acceptanceId',v_accept.id,
     'responsibleAllocationId',v_allocation.id,
     'personalPerformanceNotClaimed',v_shared_event,
     'reporterPersonId',v_actor,
     'responsiblePersonId',v_claimed_performer,
     'performanceIsWitnessedClaim',v_witnessed,
     'authorityMode',case when v_shared_event then 'event_shared_state_confirmation'
          when v_physical_care then 'source_qualified_physical_actual'
         when v_witnessed then 'ledger_governor_witness'
         else 'responsible_person_attestation' end))
 RETURNING * INTO v_event;
 -- Existing mutable state is a backward-compatible *projection* only.
 -- Old trigger chains remain present during the protected transition.
 UPDATE atlas.work_items
 SET work_state='completed',completed_at=v_completed_at,
     updated_at=v_completed_at
 WHERE id=v_work.id AND work_state='open';
 IF NOT FOUND THEN RAISE EXCEPTION 'Original Work projection drifted'
   USING ERRCODE='23514'; END IF;
 IF NOT v_shared_event AND v_allocation.state='active' THEN
   UPDATE atlas.work_allocations
     SET state='completed',completed_at=v_completed_at,updated_at=v_completed_at
   WHERE id=v_allocation.id AND state='active';
 END IF;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','universal_work_lifecycle_transition_v1',
   'idempotent',false,'eventId',v_event.id,
   'workItemId',v_work.id,'workState','completed',
   'originalResultId',v_result.id,'acceptedEvidenceId',v_accept.id,
   'reporterPersonId',v_actor,'responsiblePersonId',v_claimed_performer,
   'performanceIsWitnessedClaim',v_witnessed,
   'personalPerformanceNotClaimed',v_shared_event,
   'recordedAt',v_event.recorded_at,'effectiveAt',v_event.occurred_at);
END;
$transition$;

REVOKE ALL ON FUNCTION atlas.apply_work_lifecycle_transition_internal_v1(
 uuid,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
-- No public wrapper or authenticated EXECUTE. This cannot become an
-- alternate Done button while old completion writers are running.

-- EXACT CONTINUING WORK SOURCE
-- CROSS-PR SINGLE-DONE RELEASE HOLD (2026-10-28):
-- This assembled source still installs 02_farm_care_actual_adapter.sql,
-- whose terminal physical Work path directly updates work_items/allocations.
-- NEVER release this standalone package. The held
-- 10_care_actual_single_done_cutover_candidate.sql must be applied AFTER
-- Noel PR #2368 one-lifecycle source in protected clone, with signed actor
-- acceptance and an exact combined release/postcondition review.
-- Neither draft is authorized for production.
-- Governed ATLAS continuing original Work candidate. DRAFT ONLY.
-- No production release without full production-schema clone + signed tests.

-- SOURCE SECTION: candidate.sql
-- CANDIDATE ONLY. Do not apply to production or call from a client.
-- Reuse canonical atlas.work_items; this is a private source-to-one-serving primitive,
-- NOT an independent recurring task generator, Today writer or farm care engine.
-- Caller must already have established the exact physical/operational Need and
-- domain-specific qualifying Result contract before calling this internal primitive.
CREATE OR REPLACE FUNCTION atlas.establish_continuing_original_work_internal_v1(
  p_custody_kind text,
  p_custody_id uuid,
  p_ledger_id uuid,
  p_need_kind text,
  p_need_id uuid,
  p_serving_key text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id uuid,
  p_title text,
  p_instructions text,
  p_result_contract_key text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_rhythm atlas.rhythm_state%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_person uuid;
  v_stable_key text;
  v_existing_count integer;
  v_source_domain text;
BEGIN
  -- No arbitrary authenticated client is authorized to call this function:
  -- EXECUTE is revoked below. The only authorized caller is a governed
  -- source-owned writer that already proved the exact present Need and
  -- compatible Result, not a planner or a legacy task/clock reader.
  IF auth.uid() IS NULL OR p_custody_kind IS NULL
    OR p_custody_kind NOT IN ('household','organization')
    OR p_need_kind IS NULL OR p_subject_domain IS NULL
    OR p_subject_kind IS NULL
    OR p_custody_id IS NULL OR p_need_id IS NULL
    OR p_subject_id IS NULL OR p_result_contract_key IS NULL
    OR nullif(btrim(coalesce(p_title,'')),'') IS NULL
    OR length(p_title)>500
    OR nullif(btrim(coalesce(p_serving_key,'')),'') IS NULL
    OR length(p_serving_key)>200
    OR length(coalesce(p_instructions,''))>8000
  THEN
    RAISE EXCEPTION 'Exact signed custody, source Need, serving and result are required'
      USING ERRCODE='22023';
  END IF;

  IF p_custody_kind='household' THEN
    IF p_ledger_id IS NOT NULL OR p_need_kind<>'household_need_occurrence'
       OR p_subject_domain<>'household' OR p_subject_kind<>'kernel_instance' THEN
      RAISE EXCEPTION 'Household source cannot claim organization authority'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='household';
    v_person:=atlas.require_household_governor_self_v1(p_custody_id);
    SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
      WHERE id=p_need_id AND household_id=p_custody_id
        AND instance_id=p_subject_id AND state='open'
      FOR UPDATE;
    IF v_need.id IS NULL THEN
      RAISE EXCEPTION 'Unconfirmed or closed original Household Need'
        USING ERRCODE='23514';
    END IF;
    -- Household Work already has a source guard; preserve its exact custody,
    -- type, and policy. This helper must never silently broaden that guard.
    IF p_result_contract_key<>'household_laundry_begin_cycle_v1' THEN
      RAISE EXCEPTION 'Household Need does not have a released physical Result policy'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.household_kernel_instances inst
      WHERE inst.id=p_subject_id AND inst.household_id=p_custody_id
        AND inst.kernel_key='household.laundry' AND inst.state='active'
    ) THEN
      RAISE EXCEPTION 'Exact established Household kernel and Need are required'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.care_current_state c
      WHERE c.scope_kind='household' AND c.scope_id=p_custody_id
        AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
        AND c.subject_id=p_subject_id::text
        AND c.condition_state='ready_for_cycle'
        AND c.last_observation_id=v_need.opened_by_observation_id
    ) THEN
      RAISE EXCEPTION 'Household Need lacks current confirmed physical condition'
        USING ERRCODE='23514';
    END IF;
  ELSE
    IF p_need_kind<>'rhythm_state' OR p_ledger_id IS NULL
       OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object' THEN
      RAISE EXCEPTION 'Organization source requires exact governed jurisdiction'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='organization';
    v_person:=atlas.company_work_native_ledger_owner_self_v1(
      p_custody_id,p_ledger_id);
    SELECT * INTO v_rhythm FROM atlas.rhythm_state s
    WHERE s.id=p_need_id AND s.organization_id=p_custody_id
      AND s.subject_kind='growing_object' AND s.subject_id=p_subject_id
      AND s.state<>'paused'
      AND EXISTS (
        SELECT 1 FROM atlas.growing_objects go
        WHERE go.id=s.subject_id AND go.farm_id=s.farm_id
      )
      AND EXISTS (
        SELECT 1 FROM atlas.rhythm_bindings b
        JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
        WHERE b.id=s.rhythm_binding_id AND b.active AND r.status='active'
      )
    FOR UPDATE;
    IF v_rhythm.id IS NULL THEN
      RAISE EXCEPTION 'Absent, paused or non-actionable original Need'
        USING ERRCODE='23514';
    END IF;
    -- The domain writer, not an elapsed clock, proves immediate condition.
    -- This primitive cannot adjudicate weed pressure, mower safety, a
    -- seasonal Resting state, or stale observations. No caller is released
    -- until its domain adapter enforces those independent physical gates.
    -- A special source-qualified physical-Actual policy is also required;
    -- generic worker attestation cannot assert care state/satisfaction.
    -- It is never called by farm_rhythm_tick or by legacy task release.
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_result_contract_policies policy
    WHERE policy.contract_key=p_result_contract_key AND policy.active
      AND policy.source_domain=v_source_domain
      AND policy.acceptance_mode='domain_adapter'
      AND (
        v_source_domain='household'
        OR policy.metadata->>'continuingActualQualification'='source_proven_v1'
      )
  ) THEN
    RAISE EXCEPTION 'No active Result contract in exact native custody'
      USING ERRCODE='23514';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-work:'||p_custody_kind||':'||p_custody_id::text||
      ':'||p_need_kind||':'||p_need_id::text,0));

  -- Source-id lock prevents two concurrently valid servings for one Need.
  -- A new serving key may be used only after the previous actual Work closes.
  SELECT count(*) INTO v_existing_count FROM atlas.work_items w
  WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
      OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
    AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
    AND w.work_state='open';
  IF v_existing_count>1 THEN
    RAISE EXCEPTION 'Multiple active original Work servings for one Need'
      USING ERRCODE='23514';
  END IF;
  IF v_existing_count=1 THEN
    SELECT * INTO v_work FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
      AND w.work_state='open'
    FOR UPDATE;
    IF v_work.result_contract_key IS DISTINCT FROM p_result_contract_key THEN
      RAISE EXCEPTION 'Existing Need Work has a different Result contract'
        USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'workItemId',v_work.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'clockAdmitted',false,
      'sourceKind',p_need_kind,'sourceId',p_need_id);
  END IF;

  v_stable_key:='continuing:v1:'||md5(
    p_custody_kind||':'||p_custody_id::text||':'||
    p_need_kind||':'||p_need_id::text||':'||p_serving_key);
  -- A closed identical serving cannot be reopened via a retry.
  IF EXISTS (
    SELECT 1 FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.stable_key=v_stable_key
  ) THEN
    RAISE EXCEPTION 'This continuing Work serving already has closed history'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_items(
    organization_id,household_id,title,instructions,work_state,
    source_object_type,source_object_id,stable_key,result_contract_key,
    created_by_user_id,metadata
  ) VALUES (
    CASE WHEN p_custody_kind='organization' THEN p_custody_id ELSE NULL END,
    CASE WHEN p_custody_kind='household' THEN p_custody_id ELSE NULL END,
    p_title,p_instructions,'open',p_need_kind,p_need_id,v_stable_key,
    p_result_contract_key,auth.uid(),
    jsonb_build_object(
      'sourceContract','continuing_original_work_v1',
      'needKind',p_need_kind,'needId',p_need_id,'servingKey',p_serving_key,
      'sourceConfirmedBy','governed_domain_writer',
      'noCalendarDateInferred',true,'noClockAdmissionInferred',true)
  ) RETURNING * INTO v_work;

  INSERT INTO atlas.work_item_context_links(
    organization_id,household_id,work_item_id,subject_domain,
    subject_kind,subject_id,relation_kind,provenance,metadata
  ) VALUES (
    v_work.organization_id,v_work.household_id,v_work.id,
    p_subject_domain,p_subject_kind,p_subject_id,'acts_on',
    jsonb_build_object('needKind',p_need_kind,'needId',p_need_id,
      'sourceContract','continuing_original_work_v1'),
    '{}'::jsonb
  );

  IF p_custody_kind='household' THEN
    UPDATE atlas.household_need_occurrences_v1
    SET current_work_item_id=v_work.id,updated_at=now()
    WHERE id=v_need.id AND current_work_item_id IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Household Need already owns another original Work'
        USING ERRCODE='23514';
    END IF;
  END IF;
  -- Native Ledger relevance is NOT inferred or automatically attested here.
  -- The domain writer must establish exact source-governed Ledger relevance
  -- and original Person responsibility in the same authorized transaction,
  -- otherwise the entire source transaction must fail/roll back.

  RETURN jsonb_build_object('ok',true,'contractVersion',
    'continuing_original_work_v1','workItemId',v_work.id,
    'sourceKind',p_need_kind,'sourceId',p_need_id,
    'existingOpenServing',false,'noNewWorkCreated',false,
    'ledgerRelevanceEstablished',false,
    'responsibilityEstablished',false,'clockAdmitted',false);
END;
$function$;
-- Never expose this primitive as an executable signed-user command.
-- Only separately reviewed source domain writers may call it.
REVOKE ALL ON FUNCTION atlas.establish_continuing_original_work_internal_v1(
  text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text
) FROM PUBLIC, anon, authenticated, service_role;


-- Reuse Atlas's existing reality_continuation_v1 contract. This private
-- post-Result review is READ ONLY. A domain's signed Actual writer remains
-- responsible for accepting and recording physical truth; this function
-- cannot mark an area clear, close Work or pre-create another occurrence.
CREATE OR REPLACE FUNCTION atlas.continuing_original_work_result_continuation_internal_v1(
  p_execution_result_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $continuation$
DECLARE
  v_result atlas.work_execution_results%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_acceptance atlas.work_result_acceptances%ROWTYPE;
  v_care atlas.care_result_events%ROWTYPE;
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_rhythm atlas.rhythm_state%ROWTYPE;
  v_satisfaction atlas.rhythm_satisfactions%ROWTYPE;
  v_domain text;
  v_scope_id uuid;
  v_source_kind text;
  v_source_id uuid;
  v_decision text := 'blocked';
  v_reason text := 'source_result_not_accepted';
  v_blockers jsonb := '[]'::jsonb;
  v_current jsonb := '{}'::jsonb;
  v_refs jsonb := '[]'::jsonb;
  v_care_ref text;
  v_target jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_execution_result_id IS NULL THEN
    RAISE EXCEPTION 'An exact signed Result is required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_result FROM atlas.work_execution_results
    WHERE id=p_execution_result_id;
  IF v_result.id IS NULL THEN
    RAISE EXCEPTION 'Exact original Work Result unavailable'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=v_result.work_item_id
      AND organization_id IS NOT DISTINCT FROM v_result.organization_id
      AND household_id IS NOT DISTINCT FROM v_result.household_id;
  IF v_work.id IS NULL OR
     ((v_work.organization_id IS NULL) = (v_work.household_id IS NULL)) OR
     v_work.result_contract_key IS DISTINCT FROM v_result.result_contract_key OR
     v_work.source_object_id IS NULL OR
     v_work.source_object_type NOT IN ('household_need_occurrence','rhythm_state')
  THEN
    RAISE EXCEPTION 'Result has no supported original Need-bound Work'
      USING ERRCODE='23514';
  END IF;
  v_domain := CASE WHEN v_work.household_id IS NOT NULL
    THEN 'household' ELSE 'organization' END;
  v_scope_id := COALESCE(v_work.household_id,v_work.organization_id);
  v_source_kind:=v_work.source_object_type;
  v_source_id:=v_work.source_object_id;
  -- This is not a public reader. No raw result content or cross-scope data
  -- can leave this function through an authenticated or service-role grant.
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key=v_result.result_contract_key
      AND p.active AND p.source_domain=v_domain
      AND p.acceptance_mode='domain_adapter'
      AND (v_domain='household'
        OR p.metadata->>'continuingActualQualification'='source_proven_v1')
  ) THEN
    RAISE EXCEPTION 'Result is not qualified for source-owned continuation'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_acceptance FROM atlas.work_result_acceptances a
    WHERE a.execution_result_id=v_result.id
      AND a.work_item_id=v_work.id
      AND a.organization_id IS NOT DISTINCT FROM v_work.organization_id
      AND a.household_id IS NOT DISTINCT FROM v_work.household_id;
  v_refs:=jsonb_build_array(jsonb_build_object(
    'kind','work_execution_result','ref',v_result.id));
  IF v_acceptance.id IS NOT NULL THEN
    v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
      'kind','work_result_acceptance','ref',v_acceptance.id));
  END IF;

  IF v_domain='household' THEN
    SELECT * INTO v_need FROM atlas.household_need_occurrences_v1 n
      WHERE n.id=v_source_id AND n.household_id=v_scope_id
        AND n.current_work_item_id=v_work.id;
    IF v_need.id IS NULL OR v_result.result_contract_key IS DISTINCT FROM
        'household_laundry_begin_cycle_v1' THEN
      RAISE EXCEPTION 'Household Result has no original confirmed Need'
        USING ERRCODE='23514';
    END IF;
  ELSE
    SELECT * INTO v_rhythm FROM atlas.rhythm_state s
      WHERE s.id=v_source_id AND s.organization_id=v_scope_id
        AND s.subject_kind='growing_object';
    IF v_rhythm.id IS NULL THEN
      RAISE EXCEPTION 'Organization Result has no original governed Rhythm Need'
        USING ERRCODE='23514';
    END IF;
  END IF;

  v_current:=jsonb_build_object(
    'workState',v_work.work_state,
    'resultKind',v_result.result_kind,
    'acceptanceDecision',v_acceptance.decision);
  IF v_acceptance.id IS NULL OR v_acceptance.decision<>'accepted'
     OR v_acceptance.acceptance_kind IS DISTINCT FROM
        'source_qualified_physical_actual' THEN
    v_blockers:=jsonb_build_array('qualifying_original_result_acceptance_required');
  ELSE
    v_care_ref:=v_result.payload->>'careResultId';
    IF v_care_ref IS NULL OR v_care_ref !~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
      v_blockers:=jsonb_build_array('source_physical_actual_reference_required');
    ELSE
      SELECT * INTO v_care FROM atlas.care_result_events c
      WHERE c.id=v_care_ref::uuid
        AND c.scope_id=CASE WHEN v_domain='household'
          THEN v_scope_id ELSE v_rhythm.farm_id END
        AND c.scope_kind=CASE WHEN v_domain='household'
          THEN 'household' ELSE 'farm' END
        AND c.subject_kind=CASE WHEN v_domain='household'
          THEN 'household_kernel_instance' ELSE 'growing_object' END
        AND c.subject_id=CASE WHEN v_domain='household'
          THEN v_need.instance_id::text ELSE v_rhythm.subject_id::text END
        AND c.actor_user_id=v_result.reported_by_user_id;
      IF v_care.id IS NULL THEN
        v_blockers:=jsonb_build_array('matching_first_party_physical_actual_required');
      ELSE
        v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
          'kind','care_result_event','ref',v_care.id));
        v_current:=v_current||jsonb_build_object(
          'actualResultKind',v_care.result_kind,
          'conditionAfter',v_care.condition_after);
        IF v_domain='household' THEN
          IF v_need.state='satisfied'
             AND v_need.satisfied_by_care_result_id=v_care.id
             AND v_work.work_state='completed'
             AND v_result.result_kind='completed'
          THEN
            v_decision:='settled';
            v_reason:='original_need_satisfied_by_accepted_actual';
            -- The wash-started result ends begin_cycle ONLY. It does not
            -- establish another wash Need, or complete later Laundry stages.
          ELSE
            v_decision:='reconsider';
            v_reason:='household_need_state_requires_reconciliation';
            v_blockers:=jsonb_build_array('household_need_satisfaction_not_confirmed');
          END IF;
          v_current:=v_current||jsonb_build_object('needState',v_need.state);
        ELSE
          -- Farm satisfaction is not inferred from generic Done or a
          -- possibly-stale deadline. Require exact qualified source evidence.
          SELECT * INTO v_satisfaction FROM atlas.rhythm_satisfactions s
          WHERE s.organization_id=v_scope_id
            AND s.rhythm_state_id=v_rhythm.id
            AND s.source_id=v_care.id
            AND s.evidence->>'workItemId'=v_work.id::text
          ORDER BY s.satisfied_at DESC,s.id DESC LIMIT 1;
          IF v_satisfaction.id IS NOT NULL THEN
            v_refs:=v_refs||jsonb_build_array(jsonb_build_object(
              'kind','rhythm_satisfaction','ref',v_satisfaction.id));
            v_current:=v_current||jsonb_build_object(
              'rhythmState',v_rhythm.state,
              'satisfactionKind',v_satisfaction.satisfaction_kind,
              'nextEligibleAt',v_rhythm.due_at);
            IF v_work.work_state='completed'
               AND v_result.result_kind='completed'
               AND v_satisfaction.satisfaction_kind IN ('full','conditional')
            THEN
              v_decision:='settled';
              v_reason:='qualified_source_rhythm_satisfaction_recorded';
              -- The next window is only source eligibility, not a Work,
              -- assignment, work-on date, Today admission, or observation.
            ELSE
              v_decision:='reconsider';
              v_reason:='partial_actual_requires_original_need_review';
            END IF;
          ELSE
            v_decision:='reconsider';
            v_reason:='farm_source_satisfaction_not_established';
            v_blockers:=jsonb_build_array(
              'domain_owned_rhythm_satisfaction_required');
            v_current:=v_current||jsonb_build_object(
              'rhythmState',v_rhythm.state);
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  v_target:=jsonb_build_object(
    'target',jsonb_build_object(
      'domain',v_domain,'kind',v_source_kind,'ref',v_source_id,
      'scope',jsonb_build_object(
        CASE WHEN v_domain='household' THEN 'householdId'
          ELSE 'organizationId' END,v_scope_id)),
    'resolver',jsonb_build_object(
      'key','continuing_original_need_source_qualification','version','v1'),
    'reason',jsonb_build_object('kind',v_reason,'basisRefs',v_refs),
    'disposition',v_decision,'current',v_current,'blockers',v_blockers
  );
  RETURN atlas.reality_continuation_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_continuation_v1',
      'source',jsonb_build_object(
        'domain',v_domain,'kind','work_execution_result',
        'ref',v_result.id,'changedAt',v_result.reported_at,
        'state',v_decision),
      'targets',jsonb_build_array(v_target),
      'provenance',jsonb_build_object(
        'adapter','continuing_original_work_result_continuation_internal_v1',
        'existingCanonicalWork',true,'readOnly',true,
        'doesNotCreateWork',true,'doesNotAdvanceRhythm',true,
        'doesNotGrantAuthority',true)
    )
  );
END;
$continuation$;

-- Internal-only. Never turn cross-scope result inspection into a client
-- reader, even for service-role transport. The eventual signed domain
-- Result writer is a separate source-enforced authorization boundary.
REVOKE ALL ON FUNCTION atlas.continuing_original_work_result_continuation_internal_v1(
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE SECTION: 02_farm_care_actual_adapter.sql
-- DRAFT SOURCE CANDIDATE; requires protected-clone signed positive/negative tests.
-- This is a DOMAIN ADAPTER using universal original Work/Result/Continuation.
-- It DOES NOT create a farm task generator, legacy task, employee seat,
-- new canonical Work store, scheduled task, or automatic next original Work.
-- Apply only after candidate.sql in an isolated, authorized validation clone.
--
-- The existing Household Laundry adapter continues independently under its
-- exact source and Result guard. No generic client is allowed to invent a
-- "source-qualified" Work Result merely by passing a JSON payload.

INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
)
VALUES(
  'continuing_care_actual_v1','organization','domain_adapter',true,
  'Authenticated original responsible Person reports actual care against a governed continuing Need and physical Subject',
  jsonb_build_object(
    'continuingActualQualification','source_proven_v1',
    'requiresOriginalWork',true,'requiresExactSubject',true,
    'requiresAcceptedNativePerson',true,
    'clockDoesNotAssertCondition',true,
    'noAutogeneratedNextWork',true)
)
ON CONFLICT (contract_key) DO NOTHING;
-- Never overwrite an existing policy with different trust semantics.
DO $policy$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key='continuing_care_actual_v1'
      AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
      AND p.active
      AND p.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Care Actual contract policy does not match required source qualification';
  END IF;
END;
$policy$;

CREATE OR REPLACE FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $actual$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_weed atlas.weed_cards%ROWTYPE;
  v_mowing atlas.mowing_area_state%ROWTYPE;
  v_prior atlas.care_current_state%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_care uuid;
  v_observation uuid;
  v_acceptance uuid;
  v_satisfaction uuid;
  v_actor uuid;
  v_ledger_id uuid;
  v_source_key text;
  v_kind text := nullif(btrim(coalesce(p_actual_kind,'')),'');
  v_after text := nullif(btrim(coalesce(p_condition_after,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_before text;
  v_effect text;
  v_result_kind text;
  v_care_kind text;
  v_source_kind text;
  v_source_event text;
  v_touch jsonb;
  v_touch_index integer;
  v_renew_seconds integer;
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_tz text;
  v_boundary text;
  v_at timestamptz:=clock_timestamp();
BEGIN
  v_actor:=atlas.current_person_id_v1();
  IF auth.uid() IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
     OR p_action_id IS NULL OR v_kind IS NULL OR v_after IS NULL
     OR length(v_after)>120 OR length(coalesce(v_note,''))>1500
     OR (p_minutes IS NOT NULL AND (p_minutes<0 OR p_minutes>1440))
     OR (p_recheck_on IS NOT NULL AND p_recheck_on < (now()::date - 1))
  THEN
    RAISE EXCEPTION 'Exact signed physical Work Actual and valid observation required'
      USING ERRCODE='22023';
  END IF;
  v_source_key:='continuing-care-actual:'||p_work_item_id||':'||p_action_id;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-care-actual:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Original governed continuing Work is not available'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      AND a.assignee_canonical_person_id=v_actor
      AND a.state IN ('active','completed')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'Real native-Ledger responsible Person required'
      USING ERRCODE='42501';
  END IF;
  v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
  IF NOT atlas.person_original_work_identity_disclosed_self_v1(
        v_work.organization_id,v_ledger_id,v_work.id,v_actor)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=v_work.id
        AND rel.organization_id=v_work.organization_id
        AND rel.ledger_id=v_ledger_id AND rel.attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Original Work source and physical Subject are not disclosed'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=v_work.source_object_id
      AND s.organization_id=v_work.organization_id
      AND s.subject_kind='growing_object' FOR UPDATE;
  IF v_state.id IS NULL OR NOT EXISTS(
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on'
    ) THEN
    RAISE EXCEPTION 'Original Work is not linked to this exact physical Subject'
      USING ERRCODE='23514';
  END IF;
  -- Replays must survive a later rule retirement/physical state change;
  -- first confirm the same signed Person, original Subject and exact receipt.
  -- Authorize before replay, so a different Person cannot use the idempotency
  -- key to read someone else's Work Result.
  SELECT * INTO v_result FROM atlas.work_execution_results er
    WHERE er.organization_id=v_work.organization_id
      AND er.idempotency_key=v_source_key;
  IF v_result.id IS NOT NULL THEN
    IF v_result.work_item_id<>v_work.id
      OR v_result.reported_by_user_id IS DISTINCT FROM auth.uid()
      OR v_result.metadata->>'actualKind' IS DISTINCT FROM v_kind
      OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
      OR v_result.payload->>'note' IS DISTINCT FROM v_note
      OR v_result.payload->>'minutes' IS DISTINCT FROM p_minutes::text
      OR v_result.payload->>'recheckOn' IS DISTINCT FROM p_recheck_on::text
      OR NOT EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.organization_id=v_work.organization_id
          AND a.work_item_id=v_work.id AND a.execution_result_id=v_result.id
          AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'
      )
    THEN
      RAISE EXCEPTION 'Existing physical Actual does not match original signed action'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'contractVersion','continuing_care_actual_v1',
      'workItemId',v_work.id,'workResultId',v_result.id,'workState',v_work.work_state,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;


  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.organization_id=v_work.organization_id AND b.farm_id=v_state.farm_id
      AND b.active AND r.status='active';
  IF v_rule.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.growing_objects g
      WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id
    )
  THEN
    RAISE EXCEPTION 'Source cannot verify a current allowed care policy'
      USING ERRCODE='23514';
  END IF;

  -- No "generic done": source event type, effect, and postcondition are
  -- explicitly interpreted by the owning domain. Other domains plug in
  -- their own adapters, without changing the Work/Result lifecycle.
  IF v_state.rhythm_key='mowing' THEN
    SELECT * INTO v_mowing FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id
        AND m.organization_id=v_work.organization_id
        AND m.farm_id=v_state.farm_id FOR UPDATE;
    IF v_mowing.object_id IS NULL THEN
      RAISE EXCEPTION 'Mowing source state missing' USING ERRCODE='23514';
    END IF;
    v_source_kind:='mowing_result';v_source_event:=v_kind;
    CASE v_kind
      WHEN 'mowed_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        IF v_after<>'resting' THEN
          RAISE EXCEPTION 'Full mowing must report the resting condition' USING ERRCODE='22023';
        END IF;
      WHEN 'mowed_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        IF v_after<>'partial' THEN
          RAISE EXCEPTION 'Partial mowing must retain unfinished condition' USING ERRCODE='22023';
        END IF;
      WHEN 'acceptable_no_cut' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        IF v_after<>'acceptable' THEN
          RAISE EXCEPTION 'No-cut is an observed acceptable condition, not a mow' USING ERRCODE='22023';
        END IF;
      WHEN 'too_wet' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'too_wet' THEN RAISE EXCEPTION 'Wet-ground block must be observed' USING ERRCODE='22023'; END IF;
      WHEN 'equipment_or_area_problem' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'problem' THEN RAISE EXCEPTION 'Equipment/area problem must be observed' USING ERRCODE='22023'; END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified mowing Actual kind' USING ERRCODE='22023';
    END CASE;
  ELSE
    SELECT * INTO v_weed FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE;
    IF v_weed.id IS NULL THEN
      RAISE EXCEPTION 'Weed stewardship source state missing' USING ERRCODE='23514';
    END IF;
    CASE v_kind
      WHEN 'weeded_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        v_source_kind:='object';v_source_event:='weeded_reset';
        IF v_after<>'clear' THEN
          RAISE EXCEPTION 'Full weed restoration requires observed clear condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeded_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        v_source_kind:='object';v_source_event:='weeded';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy') THEN
          RAISE EXCEPTION 'Partial weed work must preserve residual condition' USING ERRCODE='22023';
        END IF;
      WHEN 'inspection_acceptable' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        v_source_kind:='field_log';v_source_event:='action:weed_inspection_acceptable';
        IF v_after NOT IN ('clear','row_readable') THEN
          RAISE EXCEPTION 'Acceptable weed inspection must preserve observed condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeding_blocked' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy','unknown') THEN
          RAISE EXCEPTION 'Blocked weeding must preserve real condition' USING ERRCODE='22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified weed Actual kind' USING ERRCODE='22023';
    END CASE;
  END IF;

  -- Reject invented success when the configured Rhythm doesn't recognize
  -- the submitted domain event and its effect. Blockers are evidence only.
  IF v_effect IN ('full','partial','conditional') THEN
    SELECT t.value,(t.ordinality)::integer
      INTO v_touch,v_touch_index
    FROM pg_catalog.jsonb_array_elements(v_rule.qualifying_touches)
      WITH ORDINALITY AS t(value,ordinality)
    WHERE t.value->>'effect'=v_effect
      AND t.value->>'sourceKind'=v_source_kind
      AND (
        t.value->>'sourceEvent'=v_source_event
        OR t.value->'sourceEvents' ? v_source_event
      )
      AND (
        v_kind<>'weeded_partial'
        OR t.value#>>'{payloadContains,metadata,transition}'='partial'
      )
    ORDER BY t.ordinality LIMIT 1;
    IF v_touch IS NULL THEN
      RAISE EXCEPTION 'Result does not match original governed Rhythm rule'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_work.work_state<>'open' OR v_allocation.state<>'active'
    OR v_state.state='paused' OR v_rule.status<>'active' THEN
    RAISE EXCEPTION 'Original Work or active Rhythm is no longer actionable'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_prior FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  v_before:=COALESCE(v_prior.condition_state,
     CASE WHEN v_state.rhythm_key='mowing' THEN v_mowing.status
          ELSE v_weed.current_condition END);
  IF v_prior.id IS NOT NULL AND v_prior.last_observed_at>v_at THEN
    RAISE EXCEPTION 'Newer physical observation must be reconciled first' USING ERRCODE='23514';
  END IF;
  -- No ordinary mowing is issued from a stale rhythm state. That condition
  -- gate lives at Work creation, not this legitimate worker reporting step.
  -- The worker is signing the *actual*, not a inferred result of the clock.
  INSERT INTO atlas.care_result_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    occurred_at,result_kind,condition_before,condition_after,
    minutes,minutes_known,actor_user_id,source_kind,source_key,note,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,
    'farm',v_state.farm_id,v_at,v_care_kind,v_before,v_after,
    p_minutes,(p_minutes IS NOT NULL),auth.uid(),'continuing_care_actual',
    v_source_key,v_note,
    jsonb_build_object('workItemId',v_work.id,'rhythmStateId',v_state.id,
      'physicalActualKind',v_kind,'sourceRuleId',v_rule.id,
      'actualReportedByPersonId',v_actor)
  ) RETURNING id INTO v_care;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    v_at,v_after,
    CASE WHEN v_effect='blocked' THEN 'hold'
      WHEN v_effect='partial' THEN 'intervene' ELSE 'observe' END,
    auth.uid(),'continuing_care_actual_observation',
    'continuing-care-observation:'||v_care::text,
    v_note,false,
    jsonb_build_object('careResultId',v_care,'workItemId',v_work.id)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state cs
    WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
      AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
      AND cs.subject_id=v_state.subject_id::text
      AND cs.condition_state=v_after AND cs.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Physical source readback failed'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,result_kind,result_contract_key,
    idempotency_key,payload,metadata,reported_at
  ) VALUES(
    v_work.organization_id,v_work.id,v_allocation.id,
    auth.uid(),v_result_kind,'continuing_care_actual_v1',
    v_source_key,
    jsonb_strip_nulls(jsonb_build_object(
      'careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'conditionAfter',v_after,'note',v_note,
      'minutes',p_minutes,'recheckOn',p_recheck_on)),
    jsonb_build_object('actualKind',v_kind,'rhythmStateId',v_state.id,
      'authenticatedReporterPersonId',v_actor,'nativeLedgerId',v_ledger_id),
    v_at
  ) RETURNING * INTO v_result;
  INSERT INTO atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence
  ) VALUES(
    v_work.organization_id,v_work.id,v_result.id,'accepted',
    'source_qualified_physical_actual','continuing_care_actual',
    jsonb_build_object('careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'sourceRuleId',v_rule.id,'actualReporter',v_actor)
  ) RETURNING id INTO v_acceptance;

  IF v_effect IN ('full','conditional') THEN
    v_renew_seconds:=CASE WHEN coalesce(v_touch->>'renewalIntervalSeconds','') ~ '^[1-9][0-9]*$'
      THEN (v_touch->>'renewalIntervalSeconds')::integer
      ELSE v_rule.validity_interval_seconds END;
    v_tz:=coalesce(nullif(v_rule.metadata->>'timezoneName',''),'America/Chicago');
    v_boundary:=coalesce(nullif(v_rule.metadata->>'boundaryMode',''),'exact_timestamp');
    v_warning_at:=atlas.rhythm_boundary_at_v1(v_at,
      greatest(0,v_renew_seconds-v_rule.warning_window_seconds),v_tz,v_boundary);
    v_due_at:=atlas.rhythm_boundary_at_v1(v_at,v_renew_seconds,v_tz,v_boundary);
    v_failure_at:=atlas.rhythm_boundary_at_v1(v_at,
      v_renew_seconds+v_rule.grace_window_seconds,v_tz,v_boundary);
    IF v_state.last_qualifying_satisfaction_id IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM atlas.rhythm_satisfactions old
        WHERE old.id=v_state.last_qualifying_satisfaction_id
          AND old.satisfied_at>v_at
      ) THEN
      RAISE EXCEPTION 'Existing newer satisfaction must not be reversed'
        USING ERRCODE='23514';
    END IF;
    INSERT INTO atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,
      rhythm_key,subject_kind,subject_id,satisfaction_key,satisfaction_kind,
      satisfied_at,renewal_interval_seconds,source_kind,source_id,source_event,
      policy_match,evidence,created_by_user_id
    ) VALUES(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,
      v_rule.id,v_state.rhythm_key,v_state.subject_kind,v_state.subject_id,
      'continuing-actual:'||v_result.id::text,v_effect,v_at,
      CASE WHEN v_effect='conditional' THEN v_renew_seconds ELSE NULL END,
      'continuing_care_actual',v_care,v_kind,
      jsonb_build_object('touchIndex',v_touch_index,'touch',v_touch,
        'domainActualVerified',true),
      jsonb_build_object('workItemId',v_work.id,'careResultId',v_care,
        'workResultId',v_result.id),
      auth.uid()
    ) RETURNING id INTO v_satisfaction;
    UPDATE atlas.rhythm_state SET state='resting',
      last_qualifying_satisfaction_id=v_satisfaction,
      lease_started_at=v_at,warning_at=v_warning_at,due_at=v_due_at,
      failure_at=v_failure_at,recovery_started_at=NULL,
      last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'satisfactionId',v_satisfaction,
        'actualKind',v_kind),updated_at=now()
    WHERE id=v_state.id;
  ELSIF v_effect='partial' THEN
    -- One still-open original Work; partial progress does not manufacture
    -- another occurrence. The physical state and Actual remain durable.
    UPDATE atlas.rhythm_state SET state='recovering',
      recovery_started_at=v_at,last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'careResultId',v_care,'actualKind',v_kind),
      updated_at=now()
    WHERE id=v_state.id;
  END IF;

  -- Domain projections retain actual route/bed state; other domains provide
  -- their own projections without altering canonical Work/Result machinery.
  IF v_state.rhythm_key='mowing' THEN
    UPDATE atlas.mowing_area_state SET
      status=v_after,last_observed_at=v_at,
      last_mowed_at=CASE WHEN v_kind='mowed_full' THEN v_at ELSE last_mowed_at END,
      next_check_date=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_check_date END,
      -- source_event_id references legacy mowing_events, NOT care_result_events.
      -- Preserve legacy source_event_id; the canonical Actual is in care history.
      note=v_note,metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
        updated_at=now()
    WHERE object_id=v_state.subject_id AND organization_id=v_work.organization_id;
  ELSIF v_effect IN ('full','partial','conditional') THEN
    UPDATE atlas.weed_cards SET
      current_condition=v_after,
      next_review_on=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_review_on END,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
      last_session_at=v_at,updated_at=now()
    WHERE id=v_weed.id;
  END IF;

  IF v_result_kind='completed' THEN
    UPDATE atlas.work_items SET work_state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_work.id AND work_state='open';
    UPDATE atlas.work_allocations SET state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_allocation.id AND state='active';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','continuing_care_actual_v1',
    'idempotent',false,'workItemId',v_work.id,
    'workResultId',v_result.id,'careResultId',v_care,
    'careObservationId',v_observation,'acceptanceId',v_acceptance,
    'rhythmSatisfactionId',v_satisfaction,
    'workState',CASE WHEN v_result_kind='completed' THEN 'completed' ELSE 'open' END,
    'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
    'nextEligibleAt',v_due_at,
    'noNewWorkCreated',true,'noClockAdmission',true);
END;
$actual$;

-- PRE-RELEASE HOLD. Do not grant a domain reporter to authenticated until
-- real native-Person signed positive/negative clone tests + source disclosure
-- coverage pass. Explicitly deny unsafe direct execution for now.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE SECTION: 04_care_actual_source_guards.sql
-- DRAFT; must be included AFTER 02_farm_care_actual_adapter.sql.
-- This is a SOURCE EVIDENCE GUARD for one domain adapter, not a new global
-- Work completion regime. Other domains retain their own Result policies.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_result_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.organization_id IS NULL
    OR NEW.household_id IS NOT NULL
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NEW.responsible_allocation_id IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.rhythm_state s ON s.id=w.source_object_id
        AND s.organization_id=w.organization_id
      JOIN atlas.work_allocations a ON a.id=NEW.responsible_allocation_id
        AND a.organization_id=w.organization_id
        AND a.work_item_id=w.id
      JOIN atlas.care_result_events c
        ON c.id=atlas.rhythm_safe_uuid_v1(NEW.payload->>'careResultId')
        AND c.scope_kind='farm' AND c.scope_id=s.farm_id
        AND c.subject_domain='farm' AND c.subject_kind='growing_object'
        AND c.subject_id=s.subject_id::text
        AND c.actor_user_id=NEW.reported_by_user_id
        AND c.source_kind='continuing_care_actual'
      WHERE w.id=NEW.work_item_id
        AND w.organization_id=NEW.organization_id
        AND w.source_object_type='rhythm_state'
        AND w.result_contract_key=NEW.result_contract_key
        AND w.work_state='open'
        AND a.allocation_role='responsible' AND a.state='active'
        AND a.assignee_canonical_person_id=atlas.current_person_id_v1()
        AND c.metadata->>'workItemId'=w.id::text
        AND c.metadata->>'rhythmStateId'=s.id::text
        AND c.metadata->>'physicalActualKind'=NEW.payload->>'actualKind'
        AND c.condition_after=NEW.payload->>'conditionAfter'
        AND (
          (NEW.result_kind='completed'
            AND c.result_kind IN ('recovered','condition_differed'))
          OR (NEW.result_kind='partial'
            AND c.result_kind='improved_more_remains')
          OR (NEW.result_kind='blocked'
            AND c.result_kind='blocked')
        )
    )
  THEN
    RAISE EXCEPTION 'Canonical continuing Work Result requires its accepted first-party Actual'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_result_v1
BEFORE INSERT ON atlas.work_execution_results
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_result_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_execution_results r
    WHERE r.id=NEW.execution_result_id
      AND r.organization_id=NEW.organization_id
      AND r.work_item_id=NEW.work_item_id
      AND r.result_contract_key='continuing_care_actual_v1'
  ) THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.household_id IS NOT NULL
     OR NEW.decision<>'accepted'
     OR NEW.acceptance_kind<>'source_qualified_physical_actual'
     OR NEW.accepted_by_domain<>'continuing_care_actual'
     OR NOT EXISTS (
       SELECT 1 FROM atlas.work_execution_results r
       JOIN atlas.care_result_events c
         ON c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
       WHERE r.id=NEW.execution_result_id
         AND r.organization_id=NEW.organization_id
         AND r.work_item_id=NEW.work_item_id
         AND r.reported_by_user_id=auth.uid()
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
         AND c.metadata->>'workItemId'=NEW.work_item_id::text
         AND NEW.evidence->>'careResultId'=c.id::text
     )
  THEN
    RAISE EXCEPTION 'Continuing Work acceptance requires exact authenticated physical evidence'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_acceptance_v1
BEFORE INSERT ON atlas.work_result_acceptances
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_work_completion_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF OLD.work_state IS NOT DISTINCT FROM NEW.work_state
     OR NEW.work_state<>'completed'
     OR NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF NEW.organization_id IS NULL OR NEW.household_id IS NOT NULL
     OR NOT EXISTS(
       SELECT 1
       FROM atlas.work_execution_results r
       JOIN atlas.work_result_acceptances a ON a.execution_result_id=r.id
         AND a.work_item_id=r.work_item_id AND a.organization_id=r.organization_id
         AND a.decision='accepted'
         AND a.acceptance_kind='source_qualified_physical_actual'
       JOIN atlas.care_result_events c ON
         c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
       JOIN atlas.rhythm_satisfactions s ON s.source_id=c.id
         AND s.source_kind='continuing_care_actual'
         AND s.organization_id=NEW.organization_id
         AND s.evidence->>'workItemId'=NEW.id::text
         AND s.satisfaction_kind IN ('full','conditional')
       WHERE r.work_item_id=NEW.id AND r.organization_id=NEW.organization_id
         AND r.result_contract_key=NEW.result_contract_key
         AND r.result_kind='completed'
         AND c.metadata->>'workItemId'=NEW.id::text
     )
  THEN
    RAISE EXCEPTION 'Original continuing Work cannot close without its source-qualified satisfaction'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_work_completion_v1
BEFORE UPDATE OF work_state ON atlas.work_items
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_work_completion_v1();

-- No privilege change. Trigger functions do not need exposed client EXECUTE.
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_result_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_work_completion_v1()
FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE SECTION: 05_governed_observed_need_work_writer.sql
-- DRAFT: source-observed Need → one canonical original Work → accepted
-- connected-Person responsibility → an EXPLICIT service date in existing Today.
-- This is a thin farm DOMAIN ADAPTER to universal Work, NOT a new task engine.
-- No silent assignment, inferred physical need, or auto-generated backlog.
-- Requires candidate.sql and 02_farm_care_actual_adapter.sql first.
CREATE OR REPLACE FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_rhythm_state_id uuid,
  p_scope_id uuid,
  p_observed_condition text,
  p_observation_note text,
  p_observed_at timestamptz,
  p_service_date date,
  p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $writer$
DECLARE
  v_owner uuid;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_object atlas.growing_objects%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_current atlas.care_current_state%ROWTYPE;
  v_existing atlas.work_items%ROWTYPE;
  v_work uuid;
  v_source jsonb;
  v_assignment jsonb;
  v_allocation uuid;
  v_plan uuid;
  v_observation uuid;
  v_title text;
  v_instructions text;
  v_condition text:=nullif(btrim(coalesce(p_observed_condition,'')),'');
  v_note text:=nullif(btrim(coalesce(p_observation_note,'')),'');
  v_key text;
  v_today date;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
     OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL
     OR p_action_id IS NULL OR p_observed_at IS NULL
     OR p_service_date IS NULL OR v_condition IS NULL
     OR v_note IS NULL OR length(v_note)<10 OR length(v_note)>1500
     OR p_observed_at<now()-interval '3 days'
     OR p_observed_at>now()+interval '5 minutes' THEN
    RAISE EXCEPTION 'Exact fresh source observation and deliberate Person-day decision required'
      USING ERRCODE='22023';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id FOR UPDATE;
  IF v_scope.id IS NULL OR v_scope.organization_id<>p_organization_id
    OR v_scope.ledger_id<>p_ledger_id
    OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR v_scope.scope_state<>'active'
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR v_scope.accepted_at IS NULL
    OR v_scope.coverage_mode<>'ledger_all_work'
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id) THEN
    RAISE EXCEPTION 'Existing accepted connected-Person Ledger-wide scope required'
      USING ERRCODE='42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-need-owner:'||p_organization_id||':'||p_rhythm_state_id,0));
  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
      AND s.subject_kind='growing_object' AND s.state<>'paused'
    FOR UPDATE;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Original active Subject Need unavailable' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.farm_id=v_state.farm_id AND b.organization_id=p_organization_id
      AND b.active AND r.status='active';
  SELECT * INTO v_object FROM atlas.growing_objects g
    WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id;
  v_today:=(now() at time zone
    coalesce(nullif(v_rule.metadata->>'timezoneName',''),'UTC'))::date;
  IF p_service_date<v_today-1 OR p_service_date>v_today+14 THEN
    RAISE EXCEPTION 'Person-day placement must be an explicit bounded civil date'
      USING ERRCODE='22023';
  END IF;
  IF v_rule.id IS NULL OR v_object.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f WHERE f.id=v_state.farm_id
      AND f.organization_id=p_organization_id AND f.status='active'
    ) THEN
    RAISE EXCEPTION 'Care Need is not sourced from an active governed place'
      USING ERRCODE='23514';
  END IF;

  IF v_state.rhythm_key='mowing' THEN
    IF v_condition NOT IN ('needs_inspection','ready_for_mowing','overgrown')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.mowing_area_state m
        WHERE m.object_id=v_state.subject_id
          AND m.farm_id=v_state.farm_id
          AND m.organization_id=p_organization_id AND m.status<>'closed'
      ) THEN
      RAISE EXCEPTION 'Mowing needs a real observed route and permitted condition'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and mow if warranted — '||v_object.label;
    v_instructions:='Inspect the route and ground safety. Mow only if appropriate. Report the real outcome: full, partial, acceptable no-cut, too wet, or equipment/area problem.';
  ELSE
    IF v_condition NOT IN ('needs_inspection','row_readable',
         'medium_pressure','heavy')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.weed_cards c
        WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      )
      OR NOT atlas.care_strategy_allows_ordinary_weeding_v1(
        v_state.subject_id,p_observed_at::date) THEN
      RAISE EXCEPTION 'Weeding needs an observed eligible care strategy'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and weed if warranted — '||v_object.label;
    v_instructions:='Inspect current weed condition and care strategy. Weed only if warranted. Report the real outcome: full, partial, acceptable inspection, or blocked.';
  END IF;

  -- The source Disclosure gate is NOT the same as assigning responsibility.
  -- The worker must actually be permitted to find identity AND condition.
  IF NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'identity')
    OR NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'condition')
  THEN
    RAISE EXCEPTION 'The connected Person cannot receive this protected physical Subject'
      USING ERRCODE='42501';
  END IF;

  -- Same source action is never a second original, even after completion.
  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id
    AND w.metadata->>'servingKey'=p_action_id::text
  ORDER BY w.created_at LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.metadata->>'sourceScopeId' IS DISTINCT FROM p_scope_id::text
      OR v_existing.metadata->>'sourceServiceDate' IS DISTINCT FROM p_service_date::text
      OR v_existing.metadata->>'sourceObservedCondition' IS DISTINCT FROM v_condition
      OR v_existing.metadata->>'sourceObservedAt' IS DISTINCT FROM p_observed_at::text
      OR v_existing.metadata->>'sourceObservationNoteDigest' IS DISTINCT FROM md5(v_note)
    THEN
      RAISE EXCEPTION 'Source action replay cannot change original Person, date or observed condition'
        USING ERRCODE='23505';
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Replayed action does not match the native Ledger'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','observed_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingAction',true,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;

  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id AND w.work_state='open'
  LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    -- Never reveal or reassign an existing original that belongs to another
    -- native Ledger, even when the same underlying spatial Subject is known.
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id
        AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Another governing Ledger already has the open original Work'
        USING ERRCODE='23514';
    END IF;
    -- Never overwrite another person's task/plan with a later observation.
    RETURN jsonb_build_object('ok',true,
      'contractVersion','observed_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'assignmentUnchanged',true,
      'noNewObservationCreated',true,'clockAdmitted',false);
  END IF;

  -- Do not promote the same Need while an unresolved legacy obligation
  -- still exists. Keep that older task and its history unchanged; exact
  -- legacy disposition/transfer is a separate governed owner decision.
  IF EXISTS (
    SELECT 1 FROM atlas.tasks t
    LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
    WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
      AND (
        t.metadata->>'rhythm_state_id'=v_state.id::text
        OR (o.source_kind='rhythm_state' AND o.source_id=v_state.id)
      )
  ) THEN
    RAISE EXCEPTION 'An older active task still serves this exact Need; resolve its custody before creating another original Work'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_current FROM atlas.care_current_state c
  WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
    AND c.subject_domain='farm' AND c.subject_kind='growing_object'
    AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  IF v_current.id IS NOT NULL AND v_current.last_observed_at>p_observed_at THEN
    RAISE EXCEPTION 'Newer physical state cannot be overwritten by older evidence'
      USING ERRCODE='23514';
  END IF;

  v_key:='governed-continuing-need-observation:'||p_action_id::text;
  IF EXISTS(SELECT 1 FROM atlas.care_observation_events e
    WHERE e.source_key=v_key) THEN
    RAISE EXCEPTION 'Source action already belongs to an observation; reconcile first'
      USING ERRCODE='23505';
  END IF;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    p_observed_at,v_condition,'reassess',auth.uid(),
    'governed_continuing_need_observation',v_key,v_note,false,
    jsonb_build_object('rhythmStateId',v_state.id,
      'observingGovernorPersonId',v_owner,
      'chosenLedgerId',p_ledger_id,'notClockInferred',true)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text
      AND c.condition_state=v_condition AND c.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Source observation did not become current physical state'
      USING ERRCODE='23514';
  END IF;

  v_source:=atlas.establish_continuing_original_work_internal_v1(
    'organization',p_organization_id,p_ledger_id,'rhythm_state',v_state.id,
    p_action_id::text,'spatial','growing_object',v_state.subject_id,
    left(v_title,500),v_instructions,'continuing_care_actual_v1');
  v_work:=(v_source->>'workItemId')::uuid;
  IF v_work IS NULL OR v_source->>'noNewWorkCreated' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Original Work serving was not newly established'
      USING ERRCODE='23514';
  END IF;

  -- Freeze the original signed source action: replay must be an exact
  -- repeat, never a second assignment, observation or service date.
  UPDATE atlas.work_items SET
    metadata=metadata||jsonb_build_object(
      'sourceScopeId',p_scope_id,
      'sourceServiceDate',p_service_date,
      'sourceObservedCondition',v_condition,
      'sourceObservedAt',p_observed_at::text,
      'sourceObservationNoteDigest',md5(v_note)),
    updated_at=now()
  WHERE id=v_work AND organization_id=p_organization_id;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work,p_ledger_id,'owner_attested',
    'atlas.care_observation_events:'||v_observation::text,
    'Governor explicitly chose this Ledger for Work following a fresh signed physical observation.',
    v_owner
  );

  -- Reuse the governed native Person allocation, not an employee seat.
  v_assignment:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work,p_scope_id,
    'Fresh original physical Need explicitly given under an accepted native connected-Person scope.');
  IF v_assignment->>'state' IS DISTINCT FROM 'assigned'
    OR v_assignment->>'workItemId' IS DISTINCT FROM v_work::text THEN
    RAISE EXCEPTION 'Exact native Person responsibility was not verified'
      USING ERRCODE='23514';
  END IF;
  v_allocation:=(v_assignment->>'allocationId')::uuid;

  -- Only the governor-selected service date creates this Work's Person-day
  -- plan. Rhythm due_at is NOT the Person's scheduling/attention authority.
  INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,
    plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_allocation,NULL,NULL,'active',
    p_service_date,p_service_date,p_service_date,
    'Governor explicitly chose service date for real observed continuing Need.',
    jsonb_build_object('source','observed_continuing_care_work_v1',
      'ownerPersonId',v_owner,'sourceObservationId',v_observation,
      'connectedPersonDay',true,'principalClockAdmitted',false)
  ) RETURNING id INTO v_plan;
  INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_plan,'planned',
    p_service_date,p_service_date,NULL,
    'Governor selected actual service date from observed Need',
    jsonb_build_object('sourceObservationId',v_observation,
      'governorPersonId',v_owner,'notLegacyWorkerDay',true)
  );

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','observed_continuing_care_work_v1',
    'workItemId',v_work,'rhythmStateId',v_state.id,
    'observationId',v_observation,
    'responsiblePersonId',v_scope.worker_person_id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,
    'newOriginalWorkCreated',true,
    'sourceObservationSigned',true,
    'clockAdmitted',false,'noNextWorkPrecreated',true);
END;
$writer$;

-- Denied until protected-clone signed authority/privacy tests pass. This
-- function is a source-governor operation, not a generic task creation RPC.
REVOKE ALL ON FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid
) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE SECTION: 07_legacy_rhythm_no_duplicate_task_cutover.sql
-- Exact-source compatibility gate for the currently scheduled legacy clock.
-- This does NOT change unrelated rhythms or erase old task/history records.
-- Source snapshot: atlas.ensure_rhythm_task_v1 md5
-- d195ec2ccf9b36858cba9c5bfbfb2724 on 2026-10-28.
-- Verify this fingerprint before replacing in protected clone and prior to
-- any production release; direct legacy helper entrypoints are separately
-- covered by the insert admission guards below.
CREATE OR REPLACE FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  p_state_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $body$
  SELECT COALESCE(p_state_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM atlas.rhythm_state s
    JOIN atlas.work_items w ON w.organization_id=s.organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=s.id
      AND w.metadata->>'sourceContract'='continuing_original_work_v1'
    WHERE s.id=p_state_id
  ),false);
$body$;
REVOKE ALL ON FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.ensure_rhythm_task_v1(
  p_state_id uuid,p_target_state text,p_boundary_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $body$
DECLARE
  v_state atlas.rhythm_state%ROWTYPE;
BEGIN
  SELECT state.* INTO v_state
  FROM atlas.rhythm_state state WHERE state.id=p_state_id;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Rhythm state not found.' USING ERRCODE='P0002';
  END IF;

  -- The FIRST canonical original Work is the exact Need's cutover.
  -- Retain the old rhythm clock but suppress future legacy task births from
  -- this scheduled route, including later cycles; only separately observed
  -- condition + authorization may create a new original Work.
  IF atlas.continuing_rhythm_original_work_has_custody_v1(p_state_id) THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','canonical_original_work_has_custody',
      'legacyTaskCreated',false);
  END IF;

  IF v_state.rhythm_key='weed_stewardship'
    AND v_state.subject_kind='growing_object'
    AND NOT atlas.weed_card_allows_ordinary_work_v1(
      v_state.subject_id,
      (coalesce(p_boundary_at,now()) at time zone 'America/Chicago')::date
    )
  THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','physical_weed_need_not_present',
      'objectId',v_state.subject_id,
      'clockState',p_target_state);
  END IF;

  RETURN atlas.ensure_rhythm_task_without_physical_gate_v1(
    p_state_id,p_target_state,p_boundary_at);
END;
$body$;

-- A source-owned DEFENSE-IN-DEPTH gate covers *direct* legacy task and
-- planned-occurrence insert paths not routed through ensure_rhythm_task_v1.
-- This intentionally rejects an attempted duplicate rather than silently
-- creating ambiguous history. Legacy direct writer callers may need to
-- handle the explicit cutover exception; release tests must prove no
-- uncontrolled tick retry/error churn before this source can be deployed.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $body$
DECLARE
  v_state uuid;
BEGIN
  IF TG_TABLE_NAME='planned_work_occurrences' THEN
    IF NEW.source_kind IS DISTINCT FROM 'rhythm_state' THEN RETURN NEW; END IF;
    v_state:=NEW.source_id;
  ELSIF TG_TABLE_NAME='tasks' THEN
    -- Live legacy carriers often have generated_from NULL and use only
    -- metadata.rhythm_state_id plus an occurrence; do NOT rely on the
    -- generated_from value or an unrelated generated_from_id.
    v_state:=atlas.rhythm_safe_uuid_v1(
      NEW.metadata->>'rhythm_state_id');
    IF v_state IS NULL AND NEW.planned_occurrence_id IS NOT NULL THEN
      SELECT o.source_id INTO v_state
      FROM atlas.planned_work_occurrences o
      WHERE o.id=NEW.planned_occurrence_id
        AND o.source_kind='rhythm_state';
    END IF;
    IF v_state IS NULL AND NEW.generated_from='rhythm_clock' THEN
      SELECT s.id INTO v_state FROM atlas.rhythm_state s
      WHERE s.id=NEW.generated_from_id;
    END IF;
  ELSE RETURN NEW;
  END IF;
  IF v_state IS NOT NULL
     AND atlas.continuing_rhythm_original_work_has_custody_v1(v_state) THEN
    RAISE EXCEPTION 'Legacy rhythm task carrier cannot be created after native original Work custody'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;

CREATE TRIGGER z_guard_continuing_original_rhythm_old_task_v1
BEFORE INSERT ON atlas.tasks FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

CREATE TRIGGER z_guard_continuing_original_rhythm_old_occurrence_v1
BEFORE INSERT ON atlas.planned_work_occurrences FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

REVOKE ALL ON FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
FROM PUBLIC, anon, authenticated, service_role;
-- SOURCE SECTION: 09_rhythm_state_raw_worker_disclosure_cutover.sql
-- DRAFT ONLY: source-enforced raw Rhythm state disclosure cutover.
-- Read-only production role/claims probe 2026-10-28: a current legacy
-- authenticated farm_hand had SELECT access to 181 assigned_worker rhythms,
-- including 102 growing_objects with ZERO current exact identity/condition
-- grants. Scoped Work Subject APIs must be used for selective disclosure.
-- Do not make RLS on the raw table a parallel, unrestricted farm reader.
--
-- This guard keeps existing owner, management, project and system paths.
-- It removes only the legacy worker-credential shortcut and fail-closes
-- unknown visibility values instead of trusting broad farm membership.
-- Historical assignments and rows are preserved (no UPDATE/DELETE).
-- This change MUST be validated with signed genuine Auth/REST + installed
-- schema clone before deployment; it may narrow historic farm-hand reads.
--
-- Fingerprint prevents replacing a concurrently revised source authority.
DO $drift$
DECLARE v_existing text;
BEGIN
 IF to_regprocedure('atlas.can_read_rhythm_state_v1(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Existing raw Rhythm state disclosure function missing'
     USING ERRCODE='23514';
 END IF;
 SELECT md5(pg_catalog.pg_get_functiondef(
   'atlas.can_read_rhythm_state_v1(uuid)'::regprocedure))
 INTO v_existing;
 IF v_existing <> '2b7d7019230d0a9bf172e5e1b3224db3' THEN
   RAISE EXCEPTION 'Raw Rhythm read source changed; reconcile before cutover'
     USING ERRCODE='23514';
 END IF;
END;
$drift$;

CREATE OR REPLACE FUNCTION atlas.can_read_rhythm_state_v1(p_state_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas'
AS $gate$
 SELECT coalesce((
   SELECT CASE s.visibility_scope
     WHEN 'owner' THEN atlas.is_farm_owner(s.farm_id)
     WHEN 'management' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     -- Raw Rhythm state contains full metadata, timings and source details.
     -- Neither historic farm_hand status nor assigned_user_id alone
     -- proves current native Ledger/Subject disclosure for the exact Person.
     -- Connected Persons use bounded source-disclosed original Work readers.
     WHEN 'assigned_worker' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     WHEN 'project_shared' THEN s.subject_kind='project'
       AND atlas.can_read_project(s.subject_id)
     WHEN 'system_internal' THEN atlas.is_farm_owner(s.farm_id)
     -- Unknown/new visibility must not silently restore old farm membership.
     ELSE atlas.is_farm_manager_or_owner(s.farm_id)
   END
   FROM atlas.rhythm_state s WHERE s.id=p_state_id
 ),false);
$gate$;

-- Do not change EXECUTE grants or RLS policies here: the existing
-- atlas.rhythm_state SELECT policy calls this same source function.
-- Do not create an employee seat, blanket Subject grant, or separate reader.


-- EXACT CARE DONE CUTOVER
-- INTEGRATION CANDIDATE ONLY. Exact sibling dependency: Noel PR #2368
-- apply_work_lifecycle_transition_internal_v1 (ONE immutable Done stream).
-- Do not apply this file without the common source + protected signed tests.
-- Does not introduce an alternate Work/Result/recurrence engine.

-- DRAFT SOURCE CANDIDATE; requires protected-clone signed positive/negative tests.
-- This is a DOMAIN ADAPTER using universal original Work/Result/Continuation.
-- It DOES NOT create a farm task generator, legacy task, employee seat,
-- new canonical Work store, scheduled task, or automatic next original Work.
-- Apply only after candidate.sql in an isolated, authorized validation clone.
--
-- The existing Household Laundry adapter continues independently under its
-- exact source and Result guard. No generic client is allowed to invent a
-- "source-qualified" Work Result merely by passing a JSON payload.

INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
)
VALUES(
  'continuing_care_actual_v1','organization','domain_adapter',true,
  'Authenticated original responsible Person reports actual care against a governed continuing Need and physical Subject',
  jsonb_build_object(
    'continuingActualQualification','source_proven_v1',
    'requiresOriginalWork',true,'requiresExactSubject',true,
    'requiresAcceptedNativePerson',true,
    'clockDoesNotAssertCondition',true,
    'noAutogeneratedNextWork',true)
)
ON CONFLICT (contract_key) DO NOTHING;
-- Never overwrite an existing policy with different trust semantics.
DO $policy$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key='continuing_care_actual_v1'
      AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
      AND p.active
      AND p.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Care Actual contract policy does not match required source qualification';
  END IF;
END;
$policy$;

CREATE OR REPLACE FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $actual$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_weed atlas.weed_cards%ROWTYPE;
  v_mowing atlas.mowing_area_state%ROWTYPE;
  v_prior atlas.care_current_state%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_universal_receipt jsonb;
  v_care uuid;
  v_observation uuid;
  v_acceptance uuid;
  v_satisfaction uuid;
  v_actor uuid;
  v_ledger_id uuid;
  v_source_key text;
  v_kind text := nullif(btrim(coalesce(p_actual_kind,'')),'');
  v_after text := nullif(btrim(coalesce(p_condition_after,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_before text;
  v_effect text;
  v_result_kind text;
  v_care_kind text;
  v_source_kind text;
  v_source_event text;
  v_touch jsonb;
  v_touch_index integer;
  v_renew_seconds integer;
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_tz text;
  v_boundary text;
  v_at timestamptz:=clock_timestamp();
BEGIN
  v_actor:=atlas.current_person_id_v1();
  IF auth.uid() IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
     OR p_action_id IS NULL OR v_kind IS NULL OR v_after IS NULL
     OR length(v_after)>120 OR length(coalesce(v_note,''))>1500
     OR (p_minutes IS NOT NULL AND (p_minutes<0 OR p_minutes>1440))
     OR (p_recheck_on IS NOT NULL AND p_recheck_on < (now()::date - 1))
  THEN
    RAISE EXCEPTION 'Exact signed physical Work Actual and valid observation required'
      USING ERRCODE='22023';
  END IF;
  v_source_key:='continuing-care-actual:'||p_work_item_id||':'||p_action_id;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-care-actual:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Original governed continuing Work is not available'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      AND a.assignee_canonical_person_id=v_actor
      AND a.state IN ('active','completed')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'Real native-Ledger responsible Person required'
      USING ERRCODE='42501';
  END IF;
  v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
  IF NOT atlas.person_original_work_identity_disclosed_self_v1(
        v_work.organization_id,v_ledger_id,v_work.id,v_actor)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=v_work.id
        AND rel.organization_id=v_work.organization_id
        AND rel.ledger_id=v_ledger_id AND rel.attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Original Work source and physical Subject are not disclosed'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=v_work.source_object_id
      AND s.organization_id=v_work.organization_id
      AND s.subject_kind='growing_object' FOR UPDATE;
  IF v_state.id IS NULL OR NOT EXISTS(
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on'
    ) THEN
    RAISE EXCEPTION 'Original Work is not linked to this exact physical Subject'
      USING ERRCODE='23514';
  END IF;
  -- Replays must survive a later rule retirement/physical state change;
  -- first confirm the same signed Person, original Subject and exact receipt.
  -- Authorize before replay, so a different Person cannot use the idempotency
  -- key to read someone else's Work Result.
  SELECT * INTO v_result FROM atlas.work_execution_results er
    WHERE er.organization_id=v_work.organization_id
      AND er.idempotency_key=v_source_key;
  IF v_result.id IS NOT NULL THEN
    IF v_result.work_item_id<>v_work.id
      OR v_result.reported_by_user_id IS DISTINCT FROM auth.uid()
      OR v_result.metadata->>'actualKind' IS DISTINCT FROM v_kind
      OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
      OR v_result.payload->>'note' IS DISTINCT FROM v_note
      OR v_result.payload->>'minutes' IS DISTINCT FROM p_minutes::text
      OR v_result.payload->>'recheckOn' IS DISTINCT FROM p_recheck_on::text
      OR NOT EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.organization_id=v_work.organization_id
          AND a.work_item_id=v_work.id AND a.execution_result_id=v_result.id
          AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'
      )
    THEN
      RAISE EXCEPTION 'Existing physical Actual does not match original signed action'
        USING ERRCODE='23505';
    END IF;
    IF v_result.result_kind='completed' THEN
      IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
        WHERE e.work_item_id=v_work.id
          AND e.event_kind='work_transition_applied'
          AND e.source_idempotency_key=v_source_key) THEN
        -- Same signed action returns the SAME authoritative event and timestamp.
        v_universal_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
          v_work.id,'complete',v_result.id,v_source_key);
        RETURN v_universal_receipt||jsonb_build_object(
          'physicalActualContractVersion','continuing_care_actual_v1',
          'workResultId',v_result.id,
          'careResultId',v_result.payload->'careResultId',
          'careObservationId',v_result.payload->'careObservationId',
          'noNewWorkCreated',true,'noClockAdmission',true);
      ELSIF v_work.work_state='completed' THEN
        -- An older accepted physical result is history, not a newly signed
        -- lifecycle event and NEVER a reason to reopen completed Work.
        RETURN jsonb_build_object('ok',true,'idempotent',true,
          'contractVersion','universal_work_lifecycle_transition_v1',
          'historicalRecordedCompletion',true,'newTransitionApplied',false,
          'workItemId',v_work.id,'originalResultId',v_result.id,
          'workState','completed','noNewWorkCreated',true,
          'noClockAdmission',true);
      END IF;
      RAISE EXCEPTION 'Accepted care result has no terminal lifecycle event'
        USING ERRCODE='23514';
    END IF;
    -- Partial and blocked evidence is real but never a Done receipt.
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'contractVersion','continuing_care_actual_v1',
      'workItemId',v_work.id,'workResultId',v_result.id,
      'workState',v_work.work_state,'noNewWorkCreated',true,
      'noClockAdmission',true);
  END IF;


  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.organization_id=v_work.organization_id AND b.farm_id=v_state.farm_id
      AND b.active AND r.status='active';
  IF v_rule.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.growing_objects g
      WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id
    )
  THEN
    RAISE EXCEPTION 'Source cannot verify a current allowed care policy'
      USING ERRCODE='23514';
  END IF;

  -- No "generic done": source event type, effect, and postcondition are
  -- explicitly interpreted by the owning domain. Other domains plug in
  -- their own adapters, without changing the Work/Result lifecycle.
  IF v_state.rhythm_key='mowing' THEN
    SELECT * INTO v_mowing FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id
        AND m.organization_id=v_work.organization_id
        AND m.farm_id=v_state.farm_id FOR UPDATE;
    IF v_mowing.object_id IS NULL THEN
      RAISE EXCEPTION 'Mowing source state missing' USING ERRCODE='23514';
    END IF;
    v_source_kind:='mowing_result';v_source_event:=v_kind;
    CASE v_kind
      WHEN 'mowed_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        IF v_after<>'resting' THEN
          RAISE EXCEPTION 'Full mowing must report the resting condition' USING ERRCODE='22023';
        END IF;
      WHEN 'mowed_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        IF v_after<>'partial' THEN
          RAISE EXCEPTION 'Partial mowing must retain unfinished condition' USING ERRCODE='22023';
        END IF;
      WHEN 'acceptable_no_cut' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        IF v_after<>'acceptable' THEN
          RAISE EXCEPTION 'No-cut is an observed acceptable condition, not a mow' USING ERRCODE='22023';
        END IF;
      WHEN 'too_wet' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'too_wet' THEN RAISE EXCEPTION 'Wet-ground block must be observed' USING ERRCODE='22023'; END IF;
      WHEN 'equipment_or_area_problem' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'problem' THEN RAISE EXCEPTION 'Equipment/area problem must be observed' USING ERRCODE='22023'; END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified mowing Actual kind' USING ERRCODE='22023';
    END CASE;
  ELSE
    SELECT * INTO v_weed FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE;
    IF v_weed.id IS NULL THEN
      RAISE EXCEPTION 'Weed stewardship source state missing' USING ERRCODE='23514';
    END IF;
    CASE v_kind
      WHEN 'weeded_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        v_source_kind:='object';v_source_event:='weeded_reset';
        IF v_after<>'clear' THEN
          RAISE EXCEPTION 'Full weed restoration requires observed clear condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeded_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        v_source_kind:='object';v_source_event:='weeded';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy') THEN
          RAISE EXCEPTION 'Partial weed work must preserve residual condition' USING ERRCODE='22023';
        END IF;
      WHEN 'inspection_acceptable' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        v_source_kind:='field_log';v_source_event:='action:weed_inspection_acceptable';
        IF v_after NOT IN ('clear','row_readable') THEN
          RAISE EXCEPTION 'Acceptable weed inspection must preserve observed condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeding_blocked' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy','unknown') THEN
          RAISE EXCEPTION 'Blocked weeding must preserve real condition' USING ERRCODE='22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified weed Actual kind' USING ERRCODE='22023';
    END CASE;
  END IF;

  -- Reject invented success when the configured Rhythm doesn't recognize
  -- the submitted domain event and its effect. Blockers are evidence only.
  IF v_effect IN ('full','partial','conditional') THEN
    SELECT t.value,(t.ordinality)::integer
      INTO v_touch,v_touch_index
    FROM pg_catalog.jsonb_array_elements(v_rule.qualifying_touches)
      WITH ORDINALITY AS t(value,ordinality)
    WHERE t.value->>'effect'=v_effect
      AND t.value->>'sourceKind'=v_source_kind
      AND (
        t.value->>'sourceEvent'=v_source_event
        OR t.value->'sourceEvents' ? v_source_event
      )
      AND (
        v_kind<>'weeded_partial'
        OR t.value#>>'{payloadContains,metadata,transition}'='partial'
      )
    ORDER BY t.ordinality LIMIT 1;
    IF v_touch IS NULL THEN
      RAISE EXCEPTION 'Result does not match original governed Rhythm rule'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_work.work_state<>'open' OR v_allocation.state<>'active'
    OR v_state.state='paused' OR v_rule.status<>'active' THEN
    RAISE EXCEPTION 'Original Work or active Rhythm is no longer actionable'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_prior FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  v_before:=COALESCE(v_prior.condition_state,
     CASE WHEN v_state.rhythm_key='mowing' THEN v_mowing.status
          ELSE v_weed.current_condition END);
  IF v_prior.id IS NOT NULL AND v_prior.last_observed_at>v_at THEN
    RAISE EXCEPTION 'Newer physical observation must be reconciled first' USING ERRCODE='23514';
  END IF;
  -- No ordinary mowing is issued from a stale rhythm state. That condition
  -- gate lives at Work creation, not this legitimate worker reporting step.
  -- The worker is signing the *actual*, not a inferred result of the clock.
  INSERT INTO atlas.care_result_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    occurred_at,result_kind,condition_before,condition_after,
    minutes,minutes_known,actor_user_id,source_kind,source_key,note,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,
    'farm',v_state.farm_id,v_at,v_care_kind,v_before,v_after,
    p_minutes,(p_minutes IS NOT NULL),auth.uid(),'continuing_care_actual',
    v_source_key,v_note,
    jsonb_build_object('workItemId',v_work.id,'rhythmStateId',v_state.id,
      'physicalActualKind',v_kind,'sourceRuleId',v_rule.id,
      'actualReportedByPersonId',v_actor)
  ) RETURNING id INTO v_care;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    v_at,v_after,
    CASE WHEN v_effect='blocked' THEN 'hold'
      WHEN v_effect='partial' THEN 'intervene' ELSE 'observe' END,
    auth.uid(),'continuing_care_actual_observation',
    'continuing-care-observation:'||v_care::text,
    v_note,false,
    jsonb_build_object('careResultId',v_care,'workItemId',v_work.id)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state cs
    WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
      AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
      AND cs.subject_id=v_state.subject_id::text
      AND cs.condition_state=v_after AND cs.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Physical source readback failed'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,result_kind,result_contract_key,
    idempotency_key,payload,metadata,reported_at
  ) VALUES(
    v_work.organization_id,v_work.id,v_allocation.id,
    auth.uid(),v_result_kind,'continuing_care_actual_v1',
    v_source_key,
    jsonb_strip_nulls(jsonb_build_object(
      'careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'conditionAfter',v_after,'note',v_note,
      'minutes',p_minutes,'recheckOn',p_recheck_on)),
    jsonb_build_object('actualKind',v_kind,'rhythmStateId',v_state.id,
      'authenticatedReporterPersonId',v_actor,'nativeLedgerId',v_ledger_id),
    v_at
  ) RETURNING * INTO v_result;
  INSERT INTO atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence
  ) VALUES(
    v_work.organization_id,v_work.id,v_result.id,'accepted',
    'source_qualified_physical_actual','continuing_care_actual',
    jsonb_build_object('careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'sourceRuleId',v_rule.id,'actualReporter',v_actor)
  ) RETURNING id INTO v_acceptance;

  IF v_effect IN ('full','conditional') THEN
    v_renew_seconds:=CASE WHEN coalesce(v_touch->>'renewalIntervalSeconds','') ~ '^[1-9][0-9]*$'
      THEN (v_touch->>'renewalIntervalSeconds')::integer
      ELSE v_rule.validity_interval_seconds END;
    v_tz:=coalesce(nullif(v_rule.metadata->>'timezoneName',''),'America/Chicago');
    v_boundary:=coalesce(nullif(v_rule.metadata->>'boundaryMode',''),'exact_timestamp');
    v_warning_at:=atlas.rhythm_boundary_at_v1(v_at,
      greatest(0,v_renew_seconds-v_rule.warning_window_seconds),v_tz,v_boundary);
    v_due_at:=atlas.rhythm_boundary_at_v1(v_at,v_renew_seconds,v_tz,v_boundary);
    v_failure_at:=atlas.rhythm_boundary_at_v1(v_at,
      v_renew_seconds+v_rule.grace_window_seconds,v_tz,v_boundary);
    IF v_state.last_qualifying_satisfaction_id IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM atlas.rhythm_satisfactions old
        WHERE old.id=v_state.last_qualifying_satisfaction_id
          AND old.satisfied_at>v_at
      ) THEN
      RAISE EXCEPTION 'Existing newer satisfaction must not be reversed'
        USING ERRCODE='23514';
    END IF;
    INSERT INTO atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,
      rhythm_key,subject_kind,subject_id,satisfaction_key,satisfaction_kind,
      satisfied_at,renewal_interval_seconds,source_kind,source_id,source_event,
      policy_match,evidence,created_by_user_id
    ) VALUES(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,
      v_rule.id,v_state.rhythm_key,v_state.subject_kind,v_state.subject_id,
      'continuing-actual:'||v_result.id::text,v_effect,v_at,
      CASE WHEN v_effect='conditional' THEN v_renew_seconds ELSE NULL END,
      'continuing_care_actual',v_care,v_kind,
      jsonb_build_object('touchIndex',v_touch_index,'touch',v_touch,
        'domainActualVerified',true),
      jsonb_build_object('workItemId',v_work.id,'careResultId',v_care,
        'workResultId',v_result.id),
      auth.uid()
    ) RETURNING id INTO v_satisfaction;
    UPDATE atlas.rhythm_state SET state='resting',
      last_qualifying_satisfaction_id=v_satisfaction,
      lease_started_at=v_at,warning_at=v_warning_at,due_at=v_due_at,
      failure_at=v_failure_at,recovery_started_at=NULL,
      last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'satisfactionId',v_satisfaction,
        'actualKind',v_kind),updated_at=now()
    WHERE id=v_state.id;
  ELSIF v_effect='partial' THEN
    -- One still-open original Work; partial progress does not manufacture
    -- another occurrence. The physical state and Actual remain durable.
    UPDATE atlas.rhythm_state SET state='recovering',
      recovery_started_at=v_at,last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'careResultId',v_care,'actualKind',v_kind),
      updated_at=now()
    WHERE id=v_state.id;
  END IF;

  -- Domain projections retain actual route/bed state; other domains provide
  -- their own projections without altering canonical Work/Result machinery.
  IF v_state.rhythm_key='mowing' THEN
    UPDATE atlas.mowing_area_state SET
      status=v_after,last_observed_at=v_at,
      last_mowed_at=CASE WHEN v_kind='mowed_full' THEN v_at ELSE last_mowed_at END,
      next_check_date=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_check_date END,
      -- source_event_id references legacy mowing_events, NOT care_result_events.
      -- Preserve legacy source_event_id; the canonical Actual is in care history.
      note=v_note,metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
        updated_at=now()
    WHERE object_id=v_state.subject_id AND organization_id=v_work.organization_id;
  ELSIF v_effect IN ('full','partial','conditional') THEN
    UPDATE atlas.weed_cards SET
      current_condition=v_after,
      next_review_on=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_review_on END,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
      last_session_at=v_at,updated_at=now()
    WHERE id=v_weed.id;
  END IF;

  IF v_result_kind='completed' THEN
    -- The source-specific writer has established physical Actual, observation,
    -- accepted Result and qualifying rhythm satisfaction in THIS transaction.
    -- Only the shared lifecycle may now transition original Work to Done.
    -- A denial rolls back every physical effect above atomically.
    v_universal_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
      v_work.id,'complete',v_result.id,v_source_key);
    IF v_universal_receipt->>'ok' IS DISTINCT FROM 'true'
       OR v_universal_receipt->>'contractVersion'
            IS DISTINCT FROM 'universal_work_lifecycle_transition_v1'
       OR v_universal_receipt->>'workState' IS DISTINCT FROM 'completed'
    THEN
      RAISE EXCEPTION 'Shared lifecycle did not accept the physical care Done'
        USING ERRCODE='23514';
    END IF;
    RETURN v_universal_receipt||jsonb_build_object(
      'physicalActualContractVersion','continuing_care_actual_v1',
      'workResultId',v_result.id,'careResultId',v_care,
      'careObservationId',v_observation,'acceptanceId',v_acceptance,
      'rhythmSatisfactionId',v_satisfaction,
      'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
      'nextEligibleAt',v_due_at,
      'noNewWorkCreated',true,'noClockAdmission',true);
  END IF;
  -- Partial/blocked work retains its original open identity; no universal
  -- terminal receipt is asserted, and no new work is manufactured.
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','continuing_care_actual_v1',
    'idempotent',false,'workItemId',v_work.id,
    'workResultId',v_result.id,'careResultId',v_care,
    'careObservationId',v_observation,'acceptanceId',v_acceptance,
    'rhythmSatisfactionId',v_satisfaction,'workState','open',
    'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
    'nextEligibleAt',v_due_at,
    'noNewWorkCreated',true,'noClockAdmission',true);
END;
$actual$;

-- PRE-RELEASE HOLD. Do not grant a domain reporter to authenticated until
-- real native-Person signed positive/negative clone tests + source disclosure
-- coverage pass. Explicitly deny unsafe direct execution for now.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC, anon, authenticated, service_role;

-- FICTIONAL BED 3 ONLY
-- TEST ONLY. Apply after canonical held original-Work fixture and the
-- combined #2368/#2362 SQL in a newly disposable Supabase local clone.
-- NEVER apply on Noel production, RiverSong's retained clone, or real Elm.
-- Adds ONLY fictional governed care source rows, not an employee seat.
DO $fixture_guard$
BEGIN
 IF current_database()<>'postgres'
   OR to_regclass('atlas.work_lifecycle_events_v1') IS NULL
   OR to_regprocedure('atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)') IS NULL
   OR (SELECT count(*) FROM atlas.growing_objects
       WHERE id IN ('e5200000-0000-4000-8000-000000000b03'::uuid,
                    'e5200000-0000-4000-8000-000000000b04'::uuid))<>2
   OR (SELECT count(*) FROM atlas.work_items
       WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
       AND source_object_type='rhythm_state')<>0
 THEN RAISE EXCEPTION 'Refusing care fixture outside the exact disposable signed-original-Work clone'; END IF;
END;
$fixture_guard$;

INSERT INTO atlas.rhythm_rules(
 id,organization_id,farm_id,rule_key,rhythm_key,version,label,status,
 applicability,validity_interval_seconds,warning_window_seconds,
 grace_window_seconds,qualifying_touches,failure_consequence,player_routing,
 metadata
) VALUES
('ec300000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'clone-signed-bed3-weed','weed_stewardship',1,'Fictional Bed 3 care','active',
 '{}'::jsonb,604800,86400,86400,
 '[{"effect":"full","sourceKind":"object","sourceEvent":"weeded_reset"},
   {"effect":"partial","sourceKind":"object","sourceEvent":"weeded",
    "payloadContains":{"metadata":{"transition":"partial"}}},
   {"effect":"conditional","sourceKind":"field_log",
    "sourceEvent":"action:weed_inspection_acceptable"}]'::jsonb,
 '{}'::jsonb,'{}'::jsonb,'{"timezoneName":"America/Chicago"}'::jsonb);

INSERT INTO atlas.rhythm_bindings(
 id,organization_id,farm_id,rhythm_rule_id,binding_key,inheritance_layer,
 subject_kind,subject_id,priority,active,metadata
) VALUES
('ec300000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'ec300000-0000-4000-8000-000000000001',
 'clone-signed-bed3-specific','subject_override','growing_object',
 'e5200000-0000-4000-8000-000000000b03',100,true,'{}'::jsonb);

INSERT INTO atlas.rhythm_state(
 id,organization_id,farm_id,rhythm_binding_id,rhythm_rule_id,rhythm_key,
 subject_kind,subject_id,state,effective_rule_version,visibility_scope,
 state_reason,metadata
) VALUES
('ec300000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'ec300000-0000-4000-8000-000000000002',
 'ec300000-0000-4000-8000-000000000001',
 'weed_stewardship','growing_object',
 'e5200000-0000-4000-8000-000000000b03',
 'due',1,'owner','{"source":"fictional_signed_care_proof"}'::jsonb,
 '{}'::jsonb);

INSERT INTO atlas.weed_cards(
 id,farm_id,object_id,card_key,current_condition,target_condition,metadata
) VALUES
('ec300000-0000-4000-8000-000000000004',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000b03',
 'clone-signed-bed3','heavy','clear','{}'::jsonb);

DO $post$
BEGIN
 IF (SELECT count(*) FROM atlas.rhythm_state
     WHERE id='ec300000-0000-4000-8000-000000000003'::uuid
       AND state='due')<>1
 OR (SELECT count(*) FROM atlas.work_items
     WHERE source_object_id='ec300000-0000-4000-8000-000000000003'::uuid)<>0
 THEN RAISE EXCEPTION 'Fictional care baseline pre-created Work or drifted'; END IF;
END;
$post$;

-- CROSS-DRAFT POSTCONDITIONS
-- Cross-draft ONLY: compile after #2368 shadow + single transition and
-- #2362 release_candidate (without COMMIT) + 10 care cutover.
-- Protected production-schema clone in one transaction; always ROLLBACK.
-- Structural checks do NOT prove signed positive worker authorization.
DO $care_single_done$
DECLARE
  v_done regprocedure:=to_regprocedure(
    'atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)');
  v_actual regprocedure:=to_regprocedure(
    'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)');
  v_done_sql text;
  v_actual_sql text;
  v_rejected boolean:=false;
BEGIN
  IF v_done IS NULL OR v_actual IS NULL
     OR to_regclass('atlas.work_lifecycle_events_v1') IS NULL THEN
    RAISE EXCEPTION 'One original lifecycle source and care writer must be compiled first';
  END IF;
  IF has_function_privilege('anon',v_done,'EXECUTE')
     OR has_function_privilege('authenticated',v_done,'EXECUTE')
     OR has_function_privilege('service_role',v_done,'EXECUTE')
     OR has_function_privilege('anon',v_actual,'EXECUTE')
     OR has_function_privilege('authenticated',v_actual,'EXECUTE')
     OR has_function_privilege('service_role',v_actual,'EXECUTE') THEN
    RAISE EXCEPTION 'Pre-release source writer unexpectedly executable from client';
  END IF;
  -- PostgreSQL records SET search_path TO '' in pg_proc.proconfig
  -- as the exact text search_path="" (not search_path=).
  -- Require the empty pinned path AND SECURITY DEFINER for BOTH functions;
  -- this is not a relaxation to accept any schema or mutable caller path.
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_done
       AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig)) THEN
    RAISE EXCEPTION 'Universal lifecycle authority lacks SECURITY DEFINER with empty pinned search_path';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_actual
       AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig)) THEN
    RAISE EXCEPTION 'Physical care writer lacks SECURITY DEFINER with empty pinned search_path';
  END IF;
  v_done_sql:=pg_get_functiondef(v_done);
  v_actual_sql:=pg_get_functiondef(v_actual);
  IF position('continuing_care_actual_v1' in v_done_sql)=0
     OR position('source_qualified_physical_actual' in v_done_sql)=0
     OR position('rhythm_satisfactions' in v_done_sql)=0
     OR position('atlas.apply_work_lifecycle_transition_internal_v1' in v_actual_sql)=0
     OR position('work_lifecycle_events_v1' in v_actual_sql)=0 THEN
    RAISE EXCEPTION 'Care evidence and single terminal source are not connected';
  END IF;
  IF v_actual_sql ~* 'UPDATE[[:space:]]+atlas[.]work_items[[:space:]]+SET[[:space:]]+work_state'
     OR v_actual_sql ~* 'UPDATE[[:space:]]+atlas[.]work_allocations[[:space:]]+SET[[:space:]]+state' THEN
    RAISE EXCEPTION 'Physical domain writer still has an independent Done mutation';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class c
     WHERE c.oid='atlas.work_lifecycle_events_v1'::regclass AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'Canonical lifecycle event source is not RLS protected';
  END IF;
  -- A nonexistent original cannot be completed even by the test's elevated
  -- SQL runner. This does not substitute for signed GoTrue/PostgREST tests.
  BEGIN
    PERFORM atlas.apply_work_lifecycle_transition_internal_v1(
      '00000000-0000-4000-8000-000000000090'::uuid,'complete',
      '00000000-0000-4000-8000-000000000091'::uuid,'unknown-physical-care');
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unknown physical-care transition failed to deny';
  END IF;
  RAISE NOTICE 'One draft Done path structurally linked and denied for unknown Work; signed actor and physical Result acceptance remain outstanding';
END;
$care_single_done$;

COMMIT;
