BEGIN;
-- HELD ATLAS NATIVE PERSON COMPLETION RELEASE SOURCE PACKET (UNVERSIONED).
-- Source-only candidate; NOT an executable migration or production approval.
-- Release target: existing Atlas original Work lifecycle only.
-- Historical review/cancellation and standing farm-care/P1 bridge are excluded.
SET LOCAL statement_timeout='75s';

-- EXACT HELD SOURCE: 01_current_native_person_lifecycle_source; Git blob 62e114eb2c2371450cca1a1ca851a9f2518b75f7
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

-- EXACT HELD SOURCE: 02_baseline_and_shadow_observers; Git blob 0ca69e0a604f43cf3eee442cb1edeb4ae6c1672b
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

-- Preserve old state as un-attributed historical observations, never fabricating Done.
-- Lock original writers before one-time source baseline; then install observers.
LOCK TABLE atlas.work_items,atlas.work_allocations,
 atlas.work_execution_results,atlas.work_result_acceptances,
 atlas.work_execution_plan_events IN SHARE ROW EXCLUSIVE MODE;
SELECT atlas.seed_work_lifecycle_shadow_baseline_internal_v1();

-- EXACT HELD SOURCE: 03_shadow_projection_and_observers; Git blob 4113d95c1d8ae3b1161ca5a43e344100b6120c1b
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

-- EXACT HELD SOURCE: 04_current_native_person_single_done; Git blob 3178e11863f1c6de89e07724c3b209923fd825d3
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
   OR p_transition_kind IS NULL
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
 -- SOURCE-LAW RELEASE SCOPE 2026-11-05: completion ONLY.
 -- Governor-reviewed historical cancellation is not admitted in this cutover.
 -- Historical review/retirement remains on separately held #2368 source.
 -- Never restore self-adopted membership as current Done authority.
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
 ELSIF v_allocation.establishment_basis_kind='self_adoption' THEN
   -- Decision #2392: legacy membership remains history, not a signed authority.
   -- Never re-open or auto-convert a historical original Work here.
   RAISE EXCEPTION 'Historical self-adopted responsibility requires native reconciliation'
     USING ERRCODE='42501';
 ELSIF v_allocation.assignee_canonical_person_id IS DISTINCT FROM v_actor THEN
   -- Every accepted new ordinary Done requires the native responsible Person.
   RAISE EXCEPTION 'Current native responsible Person required'
     USING ERRCODE='42501';
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

-- EXACT HELD SOURCE: 05_existing_connected_person_result_writer_cutover; Git blob 3fba08b42c4d6d9b8d8f65656ba279ce720bd7dc
-- CUTOVER-ONLY, NO PRODUCTION RELEASE. Same existing evidence writer;
-- its terminal Work updates are removed and routed through the sole
-- private lifecycle authority. Source-specific partial/blocked reporting
-- remains evidence, not Done. The old public wrapper signature is intact.
-- Requires shadow + Gate 2 authority in the same protected release.
CREATE OR REPLACE FUNCTION atlas.report_connected_person_company_work_internal_v1(p_work_item_id uuid, p_result_kind text, p_idempotency_key text, p_payload jsonb, p_mode text, p_owner_ledger_id uuid, p_witness_evidence text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_actor uuid:=atlas.current_person_id_v1();
  v_kind text:=lower(btrim(coalesce(p_result_kind,'')));
  v_mode text:=lower(btrim(coalesce(p_mode,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_evidence text:=nullif(btrim(coalesce(p_witness_evidence,'')),'');
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_existing atlas.work_execution_results%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_reporter_ipr uuid;
  v_universal_receipt jsonb;
  v_history_event uuid;
begin
  if v_uid is null or v_actor is null then
    raise exception 'Signed-in canonical reporting Person required' using errcode='42501';
  end if;
  if p_work_item_id is null or v_kind not in ('completed','partial','blocked','unable')
    or v_mode not in ('own_work','owner_witness')
    or v_key is null or length(v_key)>160
    or p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Exact Work, result, mode, idempotency and object payload required'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id for update;
  if v_work.id is null then raise exception 'Company Work not found' using errcode='P0002'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible'
      and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and a.state in ('active','completed')
    order by a.allocated_at desc limit 1;
  if v_allocation.id is null then
    raise exception 'Exact Person-native responsible allocation not found' using errcode='23514';
  end if;
  if v_mode='own_work' then
    if v_allocation.assignee_canonical_person_id<>v_actor then
      raise exception 'Only actual responsible Person can make own-work report' using errcode='42501';
    end if;

    if not atlas.person_original_work_identity_disclosed_self_v1(v_work.organization_id,(v_allocation.establishment_basis->>'nativeLedgerId')::uuid,v_work.id,v_actor)
    then raise exception 'Undisclosed original Work Subject unavailable' using errcode='42501';end if;
  else
    if v_evidence is null or length(v_evidence) not between 16 and 2000
      or (v_allocation.establishment_basis->>'nativeLedgerId') is distinct from
        p_owner_ledger_id::text
      or atlas.company_work_native_ledger_owner_self_v1(
        v_work.organization_id,p_owner_ledger_id)<>v_actor then
      raise exception 'Owner report requires exact Ledger and detailed external evidence'
        using errcode='42501';
    end if;
  end if;
  select * into v_existing from atlas.work_execution_results r
    where r.organization_id=v_work.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.work_item_id<>v_work.id or v_existing.result_kind<>v_kind
      or v_existing.responsible_allocation_id<>v_allocation.id
      or v_existing.metadata->>'reportMode' is distinct from v_mode
      or v_existing.metadata->>'authenticatedReporterPersonId'
           is distinct from v_actor::text
      or (v_mode='owner_witness' and
          v_existing.payload->>'ownerWitnessEvidence' is distinct from v_evidence)
      or (v_mode='own_work' and
          (v_existing.payload-'claimedPerformerPersonId'-'ownerWitnessEvidence')
            is distinct from p_payload) then
      raise exception 'Result idempotency collision' using errcode='23505';
    end if;
    IF v_kind='completed' THEN
      -- Existing accepted Result may predate the event-sourced cutover.
      -- A historical receipt labels it honestly; it never fabricates a new
      -- signed Done, and it cannot mark already-completed Work again.
      IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
        WHERE e.work_item_id=v_work.id
          AND e.event_kind='work_transition_applied'
          AND e.source_idempotency_key=v_key)
      THEN
        RETURN atlas.apply_work_lifecycle_transition_internal_v1(
          v_work.id,'complete',v_existing.id,v_key);
      END IF;
      IF v_work.work_state='completed' AND EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.execution_result_id=v_existing.id
          AND a.work_item_id=v_work.id AND a.decision='accepted')
      THEN
        SELECT e.id INTO v_history_event
        FROM atlas.work_lifecycle_events_v1 e
        WHERE e.work_item_id=v_work.id
          AND e.event_kind='historical_state_snapshot'
        ORDER BY e.sequence_no DESC LIMIT 1;
        RETURN jsonb_build_object(
          'ok',true,'contractVersion','universal_work_lifecycle_transition_v1',
          'idempotent',true,'historicalRecordedCompletion',true,
          'eventId',v_history_event,'workItemId',v_work.id,
          'workState','completed','originalResultId',v_existing.id,
          'sourceAccepted',true,'newTransitionApplied',false);
      END IF;
      RAISE EXCEPTION 'Existing completion has no accepted lifecycle authority'
        USING ERRCODE='23514';
    END IF;
    return jsonb_build_object('ok',true,'idempotent',true,
      'resultId',v_existing.id,'workItemId',v_work.id,
      'workState',v_work.work_state);
  end if;
  if v_work.work_state<>'open' or v_allocation.state<>'active' then
    raise exception 'Terminal Work cannot receive another result' using errcode='23514';
  end if;
  if v_work.result_contract_key<>'ordinary_company_work_worker_attestation_v1'
    or not exists(select 1 from atlas.work_result_contract_policies p
      where p.contract_key=v_work.result_contract_key and p.active
        and p.acceptance_mode='worker_attestation'
        and p.source_domain='organization') then
    raise exception 'Source-specific Work requires its authorized result channel'
      using errcode='23514';
  end if;
  select ipr.id into v_reporter_ipr
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_work.organization_id
      and ipr.person_id=v_actor and ipr.status='active'
    order by ipr.created_at limit 1;
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    reported_by_institutional_person_record_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values(
    v_work.organization_id,v_work.id,v_allocation.id,
    v_uid,null,v_reporter_ipr,
    v_kind,v_work.result_contract_key,v_key,
    p_payload||jsonb_strip_nulls(jsonb_build_object(
      'claimedPerformerPersonId',v_allocation.assignee_canonical_person_id,
      'ownerWitnessEvidence',case when v_mode='owner_witness'
        then v_evidence else null end)),
    jsonb_build_object('source','report_connected_person_company_work_internal_v1',
      'reportMode',v_mode,'authenticatedReporterPersonId',v_actor,
      'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
      'performanceIsWitnessedClaim',v_mode='owner_witness',
      'employeeSeatRequired',false)
  ) returning * into v_result;
  if v_kind='completed' then
    insert into atlas.work_result_acceptances(
      organization_id,work_item_id,execution_result_id,
      decision,acceptance_kind,accepted_by_domain,evidence,metadata
    ) values (
      v_work.organization_id,v_work.id,v_result.id,'accepted',
      case when v_mode='own_work' then 'self_responsible_person_attestation'
        else 'owner_witnessed_person_result' end,
      'organization',
      jsonb_strip_nulls(jsonb_build_object(
        'responsibleAllocationId',v_allocation.id,
        'canonicalResponsiblePersonId',v_allocation.assignee_canonical_person_id,
        'authenticatedReporterPersonId',v_actor,
        'ownerWitnessEvidence',case when v_mode='owner_witness'
          then v_evidence else null end)),
      jsonb_build_object('source','report_connected_person_company_work_internal_v1',
        'reportMode',v_mode,'notAnEmployeeWorkerDayReport',true)
    ) returning * into v_acceptance;
    -- This original source keeps the Result and Acceptance, but no longer
    -- acts as an independent completion engine or writes terminal Work.
    -- One common lifecycle writer controls the state and universal receipt.
    v_universal_receipt:=
      atlas.apply_work_lifecycle_transition_internal_v1(
        v_work.id,'complete',v_result.id,v_key);
    IF v_universal_receipt->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Single Work lifecycle transition was not accepted'
        USING ERRCODE='23514';
    END IF;
  end if;
  IF v_kind='completed' THEN
    RETURN v_universal_receipt;
  END IF;
  return jsonb_build_object('ok',true,'idempotent',false,
    'contractVersion','connected_person_company_work_result_v1',
    'workItemId',v_work.id,'resultId',v_result.id,
    'resultKind',v_kind,'workState',
      case when v_kind='completed' then 'completed' else 'open' end,
    'acceptanceDecision',v_acceptance.decision,
    'reportMode',v_mode,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,
    'reporterPersonId',v_actor,'sourceHistoryPreserved',true);
end
$function$;

-- EXACT HELD SOURCE: 06_disable_legacy_self_adopted_writer; Git blob e6f6dd4367ad84b57ff0fb65915a9b8785e941b7
-- HELD CUTOVER CANDIDATE. Owner's native-only history decision #2392.
-- Legacy self-adopted original Work and any previously accepted Results remain
-- intact as historical source evidence. They may be linked to a current Person
-- only by a separate current-Ledger governor decision; this old Result writer
-- is NOT an independent historical reviewer or a path to a new Done.
-- Unfinished historical Work is not reactivated: a present Need must qualify
-- a separate new native original Work with exact source lineage.
-- No legacy membership, employee-seat, or self-adoption record grants modern
-- Work/Done permission, even if its old membership record remains active.
-- Future signed pending evidence and owner-reviewed historical close are
-- different governed APIs, not impersonations of this writer.
CREATE OR REPLACE FUNCTION atlas.report_self_responsible_company_work_self_api_v1(
 p_work_item_id uuid,p_result_kind text,p_idempotency_key text,
 p_payload jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
BEGIN
 IF v_uid IS NULL OR v_person IS NULL THEN
   RAISE EXCEPTION 'Signed current native Person required'
     USING ERRCODE='42501';
 END IF;
 IF p_work_item_id IS NULL
   OR p_result_kind NOT IN ('completed','partial','blocked','unable')
   OR nullif(btrim(coalesce(p_idempotency_key,'')),'') IS NULL
   OR length(p_idempotency_key)>160
   OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
 THEN RAISE EXCEPTION 'Exact original Work and action required'
   USING ERRCODE='22023'; END IF;
 -- Deliberately no historic membership query, Result/Acceptance mutation,
 -- modern completion, receipt replay, or assignment transfer. Replaying
 -- old accepted source Results via this entrypoint is also not a new Done.
 RAISE EXCEPTION 'Historical self-adopted Work is reference only; current governor reconciliation required'
   USING ERRCODE='42501';
END;
$function$;

-- EXACT HELD SOURCE: 07_existing_event_shared_writer_cutover; Git blob 8f24ee85ffa841b8d1ab91da2289365d1713bec3
-- CUTOVER CANDIDATE ONLY: existing native connected-Person Event
-- shared checklist Result/Acceptance writer delegates terminal state to
-- the SAME universal event-sourced Work transition. Marking the checklist
-- never asserts physical performance. No new Done API, no permissions.
-- The native Ledger and Occurrence source guards remain unchanged.
CREATE OR REPLACE FUNCTION atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_work_item_id uuid, p_source_action_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_action text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_key text;
  v_work atlas.work_items%rowtype;
  v_result atlas.work_execution_results%rowtype;
  v_receipt atlas.work_result_acceptances%rowtype;
  v_payload jsonb;
  v_universal_receipt jsonb;
  v_history_event uuid;
begin
  if p_work_item_id is null or v_action is null or length(v_action)>128 then
    raise exception 'Exact Work and one source action ID required.' using errcode='22023';
  end if;
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if not exists (
    select 1 from atlas.work_result_contract_policies policy
    where policy.contract_key='ledger_occurrence_shared_confirmation_v1'
      and policy.active and policy.source_domain='organization'
      and policy.acceptance_mode='domain_adapter'
  ) then
    raise exception 'Ordinary shared confirmation policy unavailable.' using errcode='23514';
  end if;
  v_key:='ledger-occurrence-done:'||
    md5(p_ledger_id::text||':'||p_occurrence_id::text||':'||v_actor::text||':'||v_action);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.company_work.shared-state:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and organization_id=p_organization_id for update;
  if v_work.id is null or v_work.source_object_type is distinct from 'ledger_occurrence_shared_work'
     or v_work.source_object_id is distinct from p_occurrence_id
     or v_work.result_contract_key is distinct from 'ledger_occurrence_shared_confirmation_v1'
     or v_work.metadata->>'sourceContract' is distinct from 'ledger_occurrence_shared_work_v1'
     or v_work.metadata->>'ledgerId' is distinct from p_ledger_id::text
     or not exists (
       select 1 from atlas.work_item_context_links ctx
       join atlas.company_work_native_ledger_relevance rel
         on rel.organization_id=ctx.organization_id and rel.work_item_id=ctx.work_item_id
           and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
       where ctx.organization_id=p_organization_id and ctx.work_item_id=p_work_item_id
         and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
         and ctx.subject_id=p_occurrence_id and ctx.relation_kind='for'
     ) then
    raise exception 'Not ordinary Work of this exact Ledger Event.' using errcode='42501';
  end if;

  select * into v_result from atlas.work_execution_results r
    where r.organization_id=p_organization_id and r.idempotency_key=v_key;
  if v_result.id is not null then
    if v_result.work_item_id<>v_work.id
       or v_result.reported_by_user_id is distinct from auth.uid()
       or v_result.result_kind<>'completed'
       or v_result.result_contract_key<>v_work.result_contract_key then
      raise exception 'Shared work action idempotency collision.' using errcode='23505';
    end if;
    IF NOT EXISTS (SELECT 1 FROM atlas.work_result_acceptances acc
      WHERE acc.execution_result_id=v_result.id
        AND acc.work_item_id=v_work.id AND acc.decision='accepted'
        AND acc.acceptance_kind='shared_checklist_state_confirmation') THEN
      RAISE EXCEPTION 'Original shared Event result lacks accepted evidence'
        USING ERRCODE='42501'; END IF;
    IF EXISTS(SELECT 1 FROM atlas.work_lifecycle_events_v1 e
      WHERE e.work_item_id=v_work.id
        AND e.event_kind='work_transition_applied'
        AND e.source_idempotency_key=v_key) THEN
      RETURN atlas.apply_work_lifecycle_transition_internal_v1(
        v_work.id,'complete',v_result.id,v_key);
    END IF;
    IF v_work.work_state='completed' THEN
      SELECT e.id INTO v_history_event FROM atlas.work_lifecycle_events_v1 e
      WHERE e.work_item_id=v_work.id
        AND e.event_kind='historical_state_snapshot'
      ORDER BY e.sequence_no DESC LIMIT 1;
      RETURN jsonb_build_object('ok',true,
        'contractVersion','universal_work_lifecycle_transition_v1',
        'idempotent',true,'historicalRecordedCompletion',true,
        'newTransitionApplied',false,'eventId',v_history_event,
        'workItemId',v_work.id,'workState','completed',
        'originalResultId',v_result.id,'markedByPersonId',v_actor,
        'personalPerformanceNotClaimed',true);
    END IF;
    RAISE EXCEPTION 'Existing Event evidence has no accepted lifecycle event'
      USING ERRCODE='23514';
  end if;
  if v_work.work_state='completed' then
    -- Existing prior completion belongs to its original actor. Do not
    -- relabel that action as the current caller or fabricate a new Done.
    SELECT e.id INTO v_history_event FROM atlas.work_lifecycle_events_v1 e
    WHERE e.work_item_id=v_work.id
      AND e.event_kind='historical_state_snapshot'
    ORDER BY e.sequence_no DESC LIMIT 1;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','universal_work_lifecycle_transition_v1',
      'idempotent',false,'alreadyDone',true,'historicalRecordedCompletion',true,
      'newTransitionApplied',false,'eventId',v_history_event,
      'workItemId',v_work.id,'workState','completed',
      'markedByPersonId',null,'personalPerformanceNotClaimed',true);
  end if;
  if v_work.work_state<>'open' then
    raise exception 'Only outstanding ordinary Event Work may be marked done.'
      using errcode='23514';
  end if;
  v_payload:=jsonb_build_object(
    'stateAssertion','ordinary_shared_work_marked_done',
    'markedByPersonId',v_actor,
    'performedByPersonId',null,
    'personalPerformanceNotClaimed',true,
    'sourceActionId',v_action);
  insert into atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,reported_by_organization_membership_id,
    result_kind,result_contract_key,idempotency_key,payload,metadata
  ) values (
    p_organization_id,v_work.id,null,
    auth.uid(),null,'completed',v_work.result_contract_key,v_key,v_payload,
    jsonb_build_object('source','mark_ledger_occurrence_shared_work_done_self_api_v1',
      'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
      'actorPersonId',v_actor,'notWorkerResult',true,'allocationNotRequired',true)
  ) returning * into v_result;
  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence,metadata
  ) values (
    p_organization_id,v_work.id,v_result.id,
    'accepted','shared_checklist_state_confirmation','organization',
    jsonb_build_object('markedByPersonId',v_actor,
      'sourceActionId',v_action,'physicalPerformerAsserted',false),
    jsonb_build_object('source','ledger_occurrence_shared_work_v1',
      'authority','active_Ledger_Person_connection_exact_Event',
      'notDelegatedWorkerAcceptance',true)
  ) returning * into v_receipt;
  -- One common lifecycle command owns ALL terminal Work state. The
  -- original Event writer only validates and records the source assertion.
  v_universal_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
    v_work.id,'complete',v_result.id,v_key);
  IF v_universal_receipt->>'ok' IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION 'Shared Event lifecycle completion was not accepted'
       USING ERRCODE='23514'; END IF;
  RETURN v_universal_receipt;
end
$function$;

-- Public RPC signatures remain unchanged; no new client or role EXECUTE.
COMMIT;
