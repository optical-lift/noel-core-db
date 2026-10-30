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
-- CLONE ACL PARITY ONLY. The protected Supabase schema-only dump loses
-- some explicit GRANT/REVOKE custody from the already-released original Work
-- schema, causing the disposable clone to grant anonymous EXECUTE by default.
-- Restore *exactly* the 61 canonical original Work ACL statements extracted
-- unchanged from supabase/migrations/20261026215011_atlas_universal_original_work_integrated_v1.sql.
-- This is test-only, requires the fictional-canary guard above, and DOES NOT
-- re-create schema, change production privileges, or relax privacy assertions.
REVOKE ALL ON FUNCTION atlas.require_governed_farm_full_disclosure_self_v1(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION atlas.block_subject_disclosure_mutation_v1()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.subject_disclosure_decision_events_v1 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.has_current_subject_disclosure_v1(
 uuid,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,authenticated,anon;
REVOKE ALL ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
REVOKE ALL ON atlas.work_decomposition_groups,atlas.work_decomposition_members
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.household_need_occurrences_v1
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_work_actor_v1(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.require_household_governor_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON atlas.household_rhythm_explicit_decisions_v1
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.guard_household_rhythm_decision_immutable_v1()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_observation_self_api_v1(
 uuid,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.establish_household_laundry_original_work_self_api_v1(
 uuid,uuid,uuid,boolean,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_household_laundry_wash_started_self_api_v1(
 uuid,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.household_laundry_current_self_api_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_current_self_api_v1()
 TO authenticated;
REVOKE ALL ON FUNCTION atlas.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_original_work_focus_self_api_v1(
 uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.person_original_work_identity_disclosed_self_v1(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION atlas.native_ledger_standing_scopes_self_api_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.native_ledger_standing_scopes_self_api_v1()
 TO authenticated;
REVOKE ALL ON FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)
 TO authenticated;

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

-- HELD REAL SIGNED HTTP REPORTER (public endpoint only).
-- HELD SIGNED-HTTP ENTRYPOINT. NOT A PRODUCTION RELEASE OR ROUTE GRANT.
-- Public PostgREST function is the only executable browser care-report entry.
-- Its SECURITY DEFINER owner bridges the deliberately private domain writer.
-- Source permission is rechecked inside the domain writer for EVERY call,
-- including repeated action IDs. No user-supplied ledger, Person, or Subject
-- may override the original Work's governed allocation and context.
CREATE OR REPLACE FUNCTION public.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $signed_care$
BEGIN
  IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL THEN
    RAISE EXCEPTION 'A current signed Person is required'
      USING ERRCODE='42501';
  END IF;
  RETURN atlas.record_continuing_care_actual_self_api_v1(
    p_work_item_id,p_action_id,p_actual_kind,p_condition_after,
    p_minutes,p_note,p_recheck_on);
END;
$signed_care$;
-- PostgreSQL defaults grant EXECUTE to PUBLIC. Revoke both inherited and
-- direct anonymous privileges, then admit only genuine signed clients.
REVOKE ALL ON FUNCTION public.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) TO authenticated;
-- Invalidate PostgREST's function-signature cache inside this disposable
-- clone when the new public RPC becomes available.
SELECT pg_catalog.pg_notify('pgrst','reload schema');
-- The private writer must remain unreached even by signed or service clients.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC,anon,authenticated,service_role;


-- HELD GOVERNED STANDING SOURCE SEAM: authority + bounded physical evidence.
-- HELD DRAFT. Universal source-governed standing Work authority, version 1.
-- No new Work or Today/Clock row is created by this file. Do not deploy.
-- The only eligible source adapter presently admitted is an exact governed
-- organization Rhythm state. Future domains must add their own source gate.
-- Three distinct decisions are preserved: condition/timing, governor-selected
-- admission authority, and owner/worker source disclosure. None implies another.

CREATE TABLE atlas.continuing_work_source_governance_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 source_kind text NOT NULL CHECK (source_kind='rhythm_state'),
 source_id uuid NOT NULL,
 worker_scope_id uuid NOT NULL,
 action_id uuid NOT NULL,
 authorization_method text NOT NULL CHECK (
   authorization_method IN ('owner_each_cycle','standing_source_observed','hold')),
 governor_visibility text NOT NULL CHECK (
   governor_visibility IN ('full_eligibility','exceptions_only')),
 worker_visibility text NOT NULL CHECK (
   worker_visibility IN ('assigned_work_only','eligible_disclosed')),
 eligibility_window text NOT NULL CHECK (eligibility_window IN ('warning','due')),
 observation_max_age_seconds integer NOT NULL CHECK (
   observation_max_age_seconds BETWEEN 3600 AND 604800),
 decided_by_person_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 reason text NOT NULL CHECK (length(reason) BETWEEN 10 AND 1500),
 decision_contract text NOT NULL DEFAULT 'continuing_source_governance_v1'
   CHECK (decision_contract='continuing_source_governance_v1'),
 UNIQUE (organization_id,ledger_id,source_kind,source_id,action_id)
);
ALTER TABLE atlas.continuing_work_source_governance_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.continuing_work_source_governance_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- Immutable custody: changing a newer decision means appending a NEW event.
CREATE OR REPLACE FUNCTION atlas.block_continuing_source_governance_mutation_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $block$
BEGIN
 RAISE EXCEPTION 'Standing authority history is append-only'
 USING ERRCODE='42501';
END;
$block$;
REVOKE ALL ON FUNCTION atlas.block_continuing_source_governance_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER continuing_work_source_governance_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.continuing_work_source_governance_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_continuing_source_governance_mutation_v1();

-- Owner chooses the method at setup or replaces it only through another
-- immutable signed owner decision. No user_metadata/legacy employee seats.
CREATE OR REPLACE FUNCTION atlas.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_rhythm_state_id uuid,
 p_scope_id uuid, p_authorization_method text,
 p_governor_visibility text, p_worker_visibility text,
 p_eligibility_window text, p_observation_max_age_seconds integer,
 p_reason text, p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $decide$
DECLARE
 v_owner uuid;
 v_state atlas.rhythm_state%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_current atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_event atlas.continuing_work_source_governance_events_v1%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR atlas.current_person_id_v1() IS NULL
 OR p_organization_id IS NULL OR p_ledger_id IS NULL
 OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL OR p_action_id IS NULL
 OR p_authorization_method IS NULL OR p_authorization_method
    NOT IN ('owner_each_cycle','standing_source_observed','hold')
 OR p_governor_visibility NOT IN ('full_eligibility','exceptions_only')
 OR p_worker_visibility NOT IN ('assigned_work_only','eligible_disclosed')
 OR p_eligibility_window NOT IN ('warning','due')
 OR p_observation_max_age_seconds NOT BETWEEN 3600 AND 604800
 OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 10 AND 1500
 THEN RAISE EXCEPTION 'Complete bounded governing decision required' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner IS DISTINCT FROM atlas.current_person_id_v1() THEN
   RAISE EXCEPTION 'Only the native Ledger governor may decide source authority'
   USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-source-policy:'||p_organization_id||':'||p_ledger_id||':'||p_rhythm_state_id,0));
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
   AND s.subject_kind='growing_object' FOR SHARE;
 IF v_state.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.rhythm_bindings b JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
   WHERE b.id=v_state.rhythm_binding_id AND b.organization_id=p_organization_id
   AND b.farm_id=v_state.farm_id AND b.active
   AND r.id=v_state.rhythm_rule_id AND r.status='active'
 ) THEN
   RAISE EXCEPTION 'Only an established active native Rhythm may be governed'
   USING ERRCODE='23514';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=p_scope_id AND s.organization_id=p_organization_id
   AND s.ledger_id=p_ledger_id FOR SHARE;
 IF v_scope.id IS NULL OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
 OR v_scope.scope_state<>'active' OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
       p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN
   RAISE EXCEPTION 'Accepted, bounded connected-Person Ledger scope required'
   USING ERRCODE='42501';
 END IF;
 -- A standing authority never substitutes for the Subject disclosure decision.
 -- At configuration, do not demand disclosure (it may be granted later);
 -- eligibility and actual Work admission separately require both exact grants.
 SELECT * INTO v_event FROM atlas.continuing_work_source_governance_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.source_kind='rhythm_state' AND e.source_id=p_rhythm_state_id
 AND e.action_id=p_action_id;
 IF v_event.id IS NOT NULL THEN
   IF v_event.worker_scope_id IS DISTINCT FROM p_scope_id
   OR v_event.authorization_method IS DISTINCT FROM p_authorization_method
   OR v_event.governor_visibility IS DISTINCT FROM p_governor_visibility
   OR v_event.worker_visibility IS DISTINCT FROM p_worker_visibility
   OR v_event.eligibility_window IS DISTINCT FROM p_eligibility_window
   OR v_event.observation_max_age_seconds IS DISTINCT FROM p_observation_max_age_seconds
   OR v_event.reason IS DISTINCT FROM btrim(p_reason) THEN
      RAISE EXCEPTION 'Governing action retry cannot alter authority' USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'policyEventId',v_event.id,
     'idempotent',true,'authorizationMethod',v_event.authorization_method);
 END IF;
 SELECT * INTO v_current FROM atlas.continuing_work_source_governance_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.source_kind='rhythm_state' AND e.source_id=p_rhythm_state_id
 ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1;
 IF v_current.id IS NOT NULL AND v_current.worker_scope_id<>p_scope_id
   AND p_authorization_method<>'hold' THEN
   -- Switching the carrier is a different native connection decision.
   -- Do not silently replace an accepted Person using a new policy event.
   RAISE EXCEPTION 'Explicit hold is required before changing the entrusted carrier'
   USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.continuing_work_source_governance_events_v1(
   organization_id,ledger_id,source_kind,source_id,worker_scope_id,action_id,
   authorization_method,governor_visibility,worker_visibility,eligibility_window,
   observation_max_age_seconds,decided_by_person_id,reason
 ) VALUES(
   p_organization_id,p_ledger_id,'rhythm_state',p_rhythm_state_id,p_scope_id,p_action_id,
   p_authorization_method,p_governor_visibility,p_worker_visibility,p_eligibility_window,
   p_observation_max_age_seconds,v_owner,btrim(p_reason)
 ) RETURNING * INTO v_event;
 RETURN jsonb_build_object('ok',true,'contractVersion','continuing_source_governance_v1',
   'policyEventId',v_event.id,'idempotent',false,
   'authorizationMethod',v_event.authorization_method,
   'governorVisibility',v_event.governor_visibility,
   'workerVisibility',v_event.worker_visibility,
   'noWorkCreated',true,'noImplicitDayScheduled',true);
END;
$decide$;
REVOKE ALL ON FUNCTION atlas.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_rhythm_state_id uuid,
 p_scope_id uuid, p_authorization_method text, p_governor_visibility text,
 p_worker_visibility text, p_eligibility_window text,
 p_observation_max_age_seconds integer, p_reason text, p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.owner_decide_continuing_source_governance_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id,p_scope_id,p_authorization_method,
 p_governor_visibility,p_worker_visibility,p_eligibility_window,
 p_observation_max_age_seconds,p_reason,p_action_id);
$public$;
REVOKE ALL ON FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.owner_decide_continuing_source_governance_self_api_v1(
 uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid
) TO authenticated;

-- Read-only source eligibility, not a task generator or an owner Clock.
-- Evaluates rule time window + actual post-satisfaction physical observations.
-- Connected workers receive no source details without accepted scope AND both
-- exact identity and condition disclosure decisions, plus governor's worker
-- visibility configuration. Unconfigured sources fail closed.
CREATE OR REPLACE FUNCTION atlas.continuing_work_source_eligibility_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $eligible$
DECLARE
 v_actor uuid;
 v_owner uuid;
 v_is_owner boolean:=false;
 v_state atlas.rhythm_state%ROWTYPE;
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_rule atlas.rhythm_rules%ROWTYPE;
 v_observation atlas.care_observation_events%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_reason text:='source_unavailable';
 v_eligible boolean:=false;
 v_window_at timestamptz;
 v_last_satisfied_at timestamptz;
 v_has_open boolean:=false;
 v_legacy_open boolean:=false;
 v_physical_ok boolean:=false;
BEGIN
 v_actor:=atlas.current_person_id_v1();
 IF auth.uid() IS NULL OR v_actor IS NULL
   OR p_organization_id IS NULL OR p_ledger_id IS NULL
   OR p_rhythm_state_id IS NULL THEN
   RAISE EXCEPTION 'Signed exact Work source required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 p
 WHERE p.organization_id=p_organization_id AND p.ledger_id=p_ledger_id
 AND p.source_kind='rhythm_state' AND p.source_id=p_rhythm_state_id
 ORDER BY p.recorded_at DESC,p.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method='hold' THEN
   RAISE EXCEPTION 'Standing Work source is not currently disclosed'
   USING ERRCODE='42501';
 END IF;
 BEGIN
   v_owner:=atlas.company_work_native_ledger_owner_self_v1(
     p_organization_id,p_ledger_id);
   v_is_owner:=(v_owner=v_actor);
 EXCEPTION WHEN SQLSTATE '42501' THEN
   v_is_owner:=false;
 END;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=v_policy.worker_scope_id AND s.organization_id=p_organization_id
 AND s.ledger_id=p_ledger_id;
 IF v_scope.id IS NULL OR v_scope.scope_state<>'active'
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
       p_organization_id,p_ledger_id,v_scope.worker_person_id)
 THEN
   RAISE EXCEPTION 'Current entrusted native connection is required' USING ERRCODE='42501';
 END IF;
 IF NOT v_is_owner THEN
   IF v_actor IS DISTINCT FROM v_scope.worker_person_id
    OR v_policy.worker_visibility<>'eligible_disclosed'
    OR NOT atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_actor,'spatial','growing_object',
       (SELECT s.subject_id FROM atlas.rhythm_state s
        WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id),'identity')
    OR NOT atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_actor,'spatial','growing_object',
       (SELECT s.subject_id FROM atlas.rhythm_state s
        WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id),'condition')
   THEN
     RAISE EXCEPTION 'Standing eligibility is not disclosed to this Person'
       USING ERRCODE='42501';
   END IF;
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object';
 SELECT * INTO v_rule FROM atlas.rhythm_rules r
 JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
 WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
 AND b.organization_id=p_organization_id AND b.farm_id=v_state.farm_id
 AND b.active AND r.status='active';
 IF v_state.id IS NULL OR v_rule.id IS NULL OR v_state.state='paused'
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 OR NOT EXISTS(SELECT 1 FROM atlas.farms f
   WHERE f.id=v_state.farm_id AND f.organization_id=p_organization_id AND f.status='active')
 OR NOT EXISTS(SELECT 1 FROM atlas.growing_objects g
   WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id)
 THEN
   v_reason:='source_unavailable';
 ELSE
   v_window_at:=CASE WHEN v_policy.eligibility_window='warning'
     THEN v_state.warning_at ELSE v_state.due_at END;
   IF v_window_at IS NULL OR now()<v_window_at THEN
     v_reason:='rhythm_window_not_reached';
   ELSE
     SELECT sat.satisfied_at INTO v_last_satisfied_at
     FROM atlas.rhythm_satisfactions sat
     WHERE sat.id=v_state.last_qualifying_satisfaction_id
       AND sat.rhythm_state_id=v_state.id;
     SELECT * INTO v_current FROM atlas.care_current_state cs
     WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
       AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
       AND cs.subject_id=v_state.subject_id::text;
     SELECT * INTO v_observation FROM atlas.care_observation_events e
     WHERE e.id=v_current.last_observation_id
       AND e.scope_kind='farm' AND e.scope_id=v_state.farm_id
       AND e.subject_kind='growing_object'
       AND e.subject_id=v_state.subject_id::text
       AND NOT e.inferred_from_clock AND e.observed_by_user_id IS NOT NULL
       AND e.observed_at>coalesce(v_last_satisfied_at,'-infinity'::timestamptz)
       AND e.observed_at>=now()-
          (v_policy.observation_max_age_seconds*interval '1 second')
       AND e.observed_at<=now()+interval '5 minutes';
     IF v_current.id IS NULL OR v_observation.id IS NULL
       OR v_current.last_observed_at IS DISTINCT FROM v_observation.observed_at
       OR v_current.condition_state IS DISTINCT FROM v_observation.condition_state
     THEN
       v_reason:='fresh_physical_observation_required';
     ELSE
       IF v_state.rhythm_key='weed_stewardship' THEN
         v_physical_ok:=v_observation.condition_state IN (
           'needs_inspection','row_readable','medium_pressure','heavy')
           AND EXISTS(SELECT 1 FROM atlas.weed_cards c
             WHERE c.farm_id=v_state.farm_id AND c.object_id=v_state.subject_id)
           AND atlas.care_strategy_allows_ordinary_weeding_v1(
             v_state.subject_id,v_observation.observed_at::date);
       ELSE
         v_physical_ok:=v_observation.condition_state IN (
           'needs_inspection','ready_for_mowing','overgrown')
           AND EXISTS(SELECT 1 FROM atlas.mowing_area_state m
             WHERE m.farm_id=v_state.farm_id AND m.object_id=v_state.subject_id
             AND m.organization_id=p_organization_id AND m.status<>'closed');
       END IF;
       IF NOT v_physical_ok THEN
         v_reason:='physical_condition_or_strategy_not_eligible';
       ELSE
         SELECT EXISTS(SELECT 1 FROM atlas.work_items w
           WHERE w.organization_id=p_organization_id
           AND w.source_object_type='rhythm_state'
           AND w.source_object_id=v_state.id AND w.work_state='open')
           INTO v_has_open;
         SELECT EXISTS(
           SELECT 1 FROM atlas.tasks t
           LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
           WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
             AND (t.metadata->>'rhythm_state_id'=v_state.id::text
               OR (o.source_kind='rhythm_state' AND o.source_id=v_state.id))
         ) INTO v_legacy_open;
         IF v_has_open OR v_legacy_open THEN
           v_reason:='existing_work_already_serves_need';
         ELSE
           v_reason:='source_qualified_and_timing_eligible';
           v_eligible:=true;
         END IF;
       END IF;
     END IF;
   END IF;
 END IF;
 IF v_is_owner AND v_policy.governor_visibility='exceptions_only' AND v_eligible THEN
   RETURN jsonb_build_object('ok',true,'visible',false,
     'view','governor_exception_projection','noWorkCreated',true);
 END IF;
 -- Worker projection has no private notes, historical events, scope IDs,
 -- unrelated subjects, or private governor policy reason.
 IF NOT v_is_owner THEN
   RETURN jsonb_build_object('ok',true,'visible',true,
      'view','connected_person_disclosed_eligibility',
      'sourceId',v_state.id,'eligible',v_eligible,'reasonCode',v_reason,
      'noWorkCreated',true,'notAnAssignment',true,'notOnToday',true);
 END IF;
 RETURN jsonb_build_object('ok',true,'visible',true,
    'view','governor_eligibility',
    'sourceId',v_state.id,'eligible',v_eligible,'reasonCode',v_reason,
    'authorizationMethod',v_policy.authorization_method,
    'workerVisibility',v_policy.worker_visibility,
    'governorVisibility',v_policy.governor_visibility,
    'observationAt',v_observation.observed_at,
    'windowAt',v_window_at,
    'noWorkCreated',true,'notOnOwnerClock',true);
END;
$eligible$;
REVOKE ALL ON FUNCTION atlas.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.continuing_work_source_eligibility_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id);
$public$;
REVOKE ALL ON FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.continuing_work_source_eligibility_self_api_v1(
 uuid,uuid,uuid
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');

-- HELD: signed observation without task admission. Worker observation is
-- physical evidence, not authority to schedule or create original Work.
-- Only the current accepted connected Person for a governor's explicit
-- standing_source_observed policy may report this physical source.
CREATE OR REPLACE FUNCTION atlas.record_standing_care_observation_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid,p_rhythm_state_id uuid,
 p_condition text,p_note text,p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $observe$
DECLARE
 v_actor uuid;
 v_state atlas.rhythm_state%ROWTYPE;
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_event atlas.care_observation_events%ROWTYPE;
 v_condition text:=nullif(btrim(coalesce(p_condition,'')),'');
 v_note text:=nullif(btrim(coalesce(p_note,'')),'');
 v_key text;
BEGIN
 v_actor:=atlas.current_person_id_v1();
 IF auth.uid() IS NULL OR v_actor IS NULL OR p_organization_id IS NULL
 OR p_ledger_id IS NULL OR p_rhythm_state_id IS NULL OR p_action_id IS NULL
 OR v_condition IS NULL OR v_note IS NULL OR length(v_note) NOT BETWEEN 10 AND 1500
 THEN RAISE EXCEPTION 'Exact signed physical evidence required' USING ERRCODE='22023';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.standing-physical-observation:'||p_organization_id||':'||p_rhythm_state_id,0));
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 g
 WHERE g.organization_id=p_organization_id AND g.ledger_id=p_ledger_id
 AND g.source_kind='rhythm_state' AND g.source_id=p_rhythm_state_id
 ORDER BY g.recorded_at DESC,g.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method<>'standing_source_observed'
 OR v_policy.worker_visibility<>'eligible_disclosed' THEN
   RAISE EXCEPTION 'Worker observation not governed by active standing authority'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes a
 WHERE a.id=v_policy.worker_scope_id AND a.organization_id=p_organization_id
 AND a.ledger_id=p_ledger_id;
 IF v_scope.id IS NULL OR v_scope.worker_person_id IS DISTINCT FROM v_actor
 OR v_scope.scope_state<>'active' OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.coverage_mode<>'ledger_all_work'
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_actor
 OR v_scope.accepted_at IS NULL
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,v_actor)
 THEN RAISE EXCEPTION 'Accepted responsible Person required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object' AND s.state<>'paused' FOR SHARE;
 IF v_state.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.rhythm_bindings b JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
   WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
     AND b.organization_id=p_organization_id AND b.farm_id=v_state.farm_id
     AND b.active AND r.status='active'
 ) THEN RAISE EXCEPTION 'Observed source no longer active' USING ERRCODE='23514'; END IF;
 IF NOT atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'identity')
 OR NOT atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'condition')
 THEN RAISE EXCEPTION 'Physical Subject not disclosed to this Person' USING ERRCODE='42501';
 END IF;
 IF (v_state.rhythm_key='weed_stewardship' AND
     v_condition NOT IN ('clear','needs_inspection','row_readable','medium_pressure','heavy'))
 OR (v_state.rhythm_key='mowing' AND
     v_condition NOT IN ('resting','acceptable','needs_inspection','ready_for_mowing','overgrown','too_wet'))
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 THEN RAISE EXCEPTION 'Unqualified physical source condition' USING ERRCODE='22023'; END IF;
 IF v_state.rhythm_key='weed_stewardship' AND NOT EXISTS(
   SELECT 1 FROM atlas.weed_cards c WHERE c.farm_id=v_state.farm_id AND c.object_id=v_state.subject_id
 ) THEN RAISE EXCEPTION 'Physical weed source missing' USING ERRCODE='23514'; END IF;
 IF v_state.rhythm_key='mowing' AND NOT EXISTS(
   SELECT 1 FROM atlas.mowing_area_state m WHERE m.farm_id=v_state.farm_id
     AND m.organization_id=p_organization_id AND m.object_id=v_state.subject_id
     AND m.status<>'closed'
 ) THEN RAISE EXCEPTION 'Physical mowing source missing' USING ERRCODE='23514'; END IF;
 v_key:='standing-care-observation:'||p_organization_id||':'||p_rhythm_state_id||':'||p_action_id;
 SELECT * INTO v_event FROM atlas.care_observation_events e
 WHERE e.source_kind='standing_care_person_observation' AND e.source_key=v_key;
 IF v_event.id IS NOT NULL THEN
    IF v_event.condition_state IS DISTINCT FROM v_condition
    OR v_event.note IS DISTINCT FROM v_note
    OR v_event.observed_by_user_id IS DISTINCT FROM auth.uid()
    OR v_event.subject_id IS DISTINCT FROM v_state.subject_id::text
    THEN RAISE EXCEPTION 'Signed physical source action replay changed meaning'
      USING ERRCODE='23505'; END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'sourceObservationId',v_event.id,'noWorkCreated',true,'notOnToday',true);
 END IF;
 SELECT * INTO v_current FROM atlas.care_current_state c
 WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
 AND c.subject_domain='farm' AND c.subject_kind='growing_object'
 AND c.subject_id=v_state.subject_id::text FOR UPDATE;
 INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
 ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    clock_timestamp(),v_condition,'reassess',auth.uid(),
    'standing_care_person_observation',v_key,v_note,false,
    jsonb_build_object('rhythmStateId',v_state.id,'ledgerId',p_ledger_id,
      'workerPersonId',v_actor,'governanceEventId',v_policy.id,
      'noAutomaticWorkCreated',true)
 ) RETURNING * INTO v_event;
 IF NOT EXISTS(SELECT 1 FROM atlas.care_current_state c
   WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
     AND c.subject_domain='farm' AND c.subject_kind='growing_object'
     AND c.subject_id=v_state.subject_id::text
     AND c.last_observation_id=v_event.id
     AND c.condition_state=v_condition
 ) THEN RAISE EXCEPTION 'Signed physical evidence failed source projection' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'idempotent',false,
   'sourceObservationId',v_event.id,'conditionRecorded',true,
   'noWorkCreated',true,'notOnToday',true,'notAnAssignment',true);
END;
$observe$;
REVOKE ALL ON FUNCTION atlas.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.record_standing_care_observation_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_condition text,p_note text,p_action_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.record_standing_care_observation_self_api_v1(
   p_organization_id,p_ledger_id,p_rhythm_state_id,p_condition,p_note,p_action_id);
$public$;
REVOKE ALL ON FUNCTION public.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_standing_care_observation_self_api_v1(
 uuid,uuid,uuid,text,text,uuid
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');

-- STRUCTURAL HOLD, not signed end-user acceptance.
-- Draft protected-clone structural postconditions. Cannot replace
-- independently signed owner/worker/outsider/anonymous HTTP acceptance.
DO $standing_policy$
DECLARE
 v_table regclass:=to_regclass('atlas.continuing_work_source_governance_events_v1');
 v_policy regprocedure:=to_regprocedure('atlas.owner_decide_continuing_source_governance_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid)');
 v_public_policy regprocedure:=to_regprocedure('public.owner_decide_continuing_source_governance_self_api_v1(uuid,uuid,uuid,uuid,text,text,text,text,integer,text,uuid)');
 v_eligibility regprocedure:=to_regprocedure('atlas.continuing_work_source_eligibility_self_api_v1(uuid,uuid,uuid)');
 v_public_eligibility regprocedure:=to_regprocedure('public.continuing_work_source_eligibility_self_api_v1(uuid,uuid,uuid)');
 v_observation regprocedure:=to_regprocedure('atlas.record_standing_care_observation_self_api_v1(uuid,uuid,uuid,text,text,uuid)');
 v_public_observation regprocedure:=to_regprocedure('public.record_standing_care_observation_self_api_v1(uuid,uuid,uuid,text,text,uuid)');
 v_sql text;
BEGIN
 IF v_table IS NULL OR v_policy IS NULL OR v_public_policy IS NULL
 OR v_eligibility IS NULL OR v_public_eligibility IS NULL
 OR v_observation IS NULL OR v_public_observation IS NULL
 THEN RAISE EXCEPTION 'Standing authority, eligibility, and signed physical evidence sources required'; END IF;
 IF NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid=v_table)
 OR has_table_privilege('anon',v_table,'SELECT')
 OR has_table_privilege('authenticated',v_table,'SELECT')
 OR has_table_privilege('authenticated',v_table,'INSERT')
 OR has_table_privilege('service_role',v_table,'INSERT') THEN
   RAISE EXCEPTION 'Raw standing authority history is exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=v_table
   AND t.tgname='continuing_work_source_governance_append_only_v1'
   AND NOT t.tgisinternal) THEN
   RAISE EXCEPTION 'Standing authority event history must be immutable'; END IF;
 IF has_function_privilege('anon',v_policy,'EXECUTE')
 OR has_function_privilege('authenticated',v_policy,'EXECUTE')
 OR has_function_privilege('service_role',v_policy,'EXECUTE')
 OR has_function_privilege('anon',v_eligibility,'EXECUTE')
 OR has_function_privilege('authenticated',v_eligibility,'EXECUTE')
 OR has_function_privilege('anon',v_observation,'EXECUTE')
 OR has_function_privilege('authenticated',v_observation,'EXECUTE')
 OR has_function_privilege('anon',v_public_policy,'EXECUTE')
 OR has_function_privilege('anon',v_public_eligibility,'EXECUTE')
 OR has_function_privilege('anon',v_public_observation,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_policy,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_eligibility,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public_observation,'EXECUTE')
 THEN
   RAISE EXCEPTION 'Signed public and restricted private standing seams are not separated';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_eligibility
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_policy
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_observation
   AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 THEN RAISE EXCEPTION 'Standing source functions require fixed empty search paths'; END IF;
 v_sql:=pg_get_functiondef(v_eligibility);
 IF position('last_qualifying_satisfaction_id' IN v_sql)=0
 OR position('inferred_from_clock' IN v_sql)=0
 OR position('last_observation_id' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('work_items' IN v_sql)=0
 OR position('planned_work_occurrences' IN v_sql)=0
 THEN RAISE EXCEPTION 'Standing eligibility must check physical source, policy and prior Work'; END IF;
 IF v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
 OR v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_execution_plans'
 THEN RAISE EXCEPTION 'Eligibility read source must not fabricate original Work or date'; END IF;
 v_sql:=pg_get_functiondef(v_observation);
 IF position('auth.uid()' IN v_sql)=0
 OR position('standing_source_observed' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('care_observation_events' IN v_sql)=0
 OR position('person_has_native_ledger_connection_v1' IN v_sql)=0
 THEN RAISE EXCEPTION 'Signed physical evidence lacks real Person or current source gates'; END IF;
 IF v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_items'
 OR v_sql ~* 'INSERT[[:space:]]+INTO[[:space:]]+atlas[.]work_execution_plans'
 THEN RAISE EXCEPTION 'Worker observation cannot generate Work or schedule Today'; END IF;
 RAISE NOTICE 'Standing source policy and current physical evidence are source-governed. Work admission remains a separate gate.';
END;
$standing_policy$;


-- VERIFIED NATIVE AUTHORITY SOURCE
-- HELD EXACT-BASELINE NATIVE GUARD EXTENSION. This IS NOT a new seat.
-- Only the preauthorized worker who signed a current source-policy action
-- may establish the existing delegated_under_standing_scope allocation.
-- All original owner paths and unrelated ledgers are copied unchanged.
-- Fail before replacing functions if the native source has drifted.
DO $native_guard_baseline$
BEGIN
 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
    'atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure)
    <> 'f5a80130cc2f204cf6e72be8f2dc23d5'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
    'atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)'::regprocedure)
    <> '7570082f04024397227545e685a4c071'
 THEN RAISE EXCEPTION 'Existing native source authorization changed; human reconciliation required'; END IF;
END;
$native_guard_baseline$;

-- Extend only source_verified evidence options. The original owner and
-- participant attestation branch, required source identity and timestamp
-- remain exact. Without this check, a verified native governance event could
-- never be the lawful source of an original Work Ledger relationship.
DO $relevance_baseline$
BEGIN
 IF (SELECT pg_get_constraintdef(c.oid)
   FROM pg_constraint c
   WHERE c.conrelid='atlas.company_work_native_ledger_relevance'::regclass
   AND c.conname='company_work_relevance_evidence_separation_v1')
   NOT LIKE '%source_schema = ''ledger''%'
 THEN RAISE EXCEPTION 'Native Ledger relevance evidence contract changed'; END IF;
END;
$relevance_baseline$;
ALTER TABLE atlas.company_work_native_ledger_relevance
 DROP CONSTRAINT company_work_relevance_evidence_separation_v1;
ALTER TABLE atlas.company_work_native_ledger_relevance
 ADD CONSTRAINT company_work_relevance_evidence_separation_v1 CHECK (
  ((evidence_kind IN ('owner_attested','participant_attested'))
    AND nullif(btrim(attestation_source_ref),'') IS NOT NULL
    AND nullif(btrim(attestation_reason),'') IS NOT NULL
    AND source_schema IS NULL AND source_table IS NULL
    AND source_id IS NULL AND verified_at IS NULL)
  OR (evidence_kind='source_verified'
    AND attestation_source_ref IS NULL AND attestation_reason IS NULL
    AND source_id IS NOT NULL AND verified_at IS NOT NULL
    AND ((source_schema='ledger'
      AND source_table IN ('booking_requests','booking_offerings'))
      OR (source_schema='atlas'
        AND source_table='continuing_work_source_governance_events_v1')))
 );

-- Exact source verified Ledger relevance for owner-approved standing Work.
CREATE OR REPLACE FUNCTION atlas.company_work_native_ledger_exact_source_v1(p_work_item_id uuid, p_ledger_id uuid)
 RETURNS TABLE(source_schema text, source_table text, source_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select 'ledger'::text,'booking_requests'::text,b.id
  from atlas.work_items w
  join ledger.booking_requests b
    on w.source_object_type='ledger_booking_request'
   and w.source_object_id=b.id
  where w.id=p_work_item_id and b.ledger_id=p_ledger_id
  union all
  select 'ledger'::text,'booking_offerings'::text,o.id
  from atlas.work_items w
  join ledger.booking_offerings o
    on w.source_object_type='ledger_booking_offering'
   and w.source_object_id=o.id
  where w.id=p_work_item_id and o.ledger_id=p_ledger_id
  union all
  select 'atlas'::text,
         'continuing_work_source_governance_events_v1'::text,
         authority.id
  from atlas.work_items w
  join atlas.continuing_work_source_governance_events_v1 authority
    on authority.id::text=w.metadata->>'standingPolicyEventId'
   and authority.organization_id=w.organization_id
   and authority.source_kind='rhythm_state'
   and authority.source_id=w.source_object_id
  where w.id=p_work_item_id and authority.ledger_id=p_ledger_id
    and w.source_object_type='rhythm_state'
    and w.result_contract_key='continuing_care_actual_v1'
    and w.metadata->>'sourceContract'='continuing_original_work_v1'
    and w.metadata->>'sourceScopeId'=authority.worker_scope_id::text;
$function$;

-- Native Person responsibility under signed accepted owner authority.
CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake',
    'ledger_connection_direct_assignment',
    'original_subject_direct_assignment_v1'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.

  -- A rooted native Ledger owner may issue an existing, source-bound Event
  -- obligation to another actual Person connected to the same Ledger.
  -- Unlike the legacy Event checklist, this uses the ORIGINAL Company Work ID.
  -- No employee membership, impersonation or synthetic worker assent.
  -- This is direct responsibility for an EXISTING original Work ID, not
  -- ledger_direct_create_work and not a new Company/farm task.
  if v_kind='original_subject_direct_assignment_v1' then
    if v_source<>'original_subject_direct_assignment_v1'
       or new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'decompositionId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_exact_existing_original_work'
    then
      raise exception 'Exact original Work direct responsibility source fields missing'
        using errcode='23514';
    end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
          is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
       or not exists(
         select 1 from atlas.work_decomposition_members m
         join atlas.work_decomposition_groups g on g.id=m.group_id
         join atlas.work_items w on w.id=m.child_work_item_id
         join atlas.company_work_native_ledger_relevance r
           on r.work_item_id=w.id and r.organization_id=w.organization_id
          and r.ledger_id=g.authorized_ledger_id and r.attribution_state='active'
         where m.child_work_item_id=new.work_item_id
           and g.id=(v_basis->>'decompositionId')::uuid
           and g.authorized_ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and w.organization_id=new.organization_id
           and w.work_state='open' and w.source_object_type='work_decomposition'
           and w.metadata->>'originalParentWorkItemId'=g.parent_work_item_id::text
       ) then
       raise exception 'Exact original Work, connection or governing authority unavailable'
         using errcode='23514';
    end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment'
     and v_source='existing_event_work_connected_direct_assignment_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'occurrenceId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>
          'governing_principal_and_active_mutual_ledger_connections'
    then raise exception 'Existing Event obligation lacks exact governing Person, Work, Ledger and Event basis'
      using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
           is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
           new.assignee_canonical_person_id)
       or not exists(select 1 from atlas.work_items w
          join atlas.work_item_context_links ctx on ctx.work_item_id=w.id
           and ctx.organization_id=w.organization_id
           and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
           and ctx.subject_id=(v_basis->>'occurrenceId')::uuid
          join atlas.company_work_native_ledger_relevance rel
           on rel.work_item_id=w.id and rel.organization_id=w.organization_id
           and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and rel.attribution_state='active'
          where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.result_contract_key='ordinary_company_work_worker_attestation_v1'
           and not exists(select 1 from atlas.ledger_occurrence_work_actions_v1 a
            where a.ledger_id=rel.ledger_id
             and a.occurrence_id=ctx.subject_id
             and a.work_item_id=w.id and a.action_kind='removed'))
    then raise exception 'Original Event Work or lawful owner/Person Ledger relationship is unavailable'
      using errcode='23514';end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>'source','')<>'ledger_connected_direct_assignment_v1'
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'nativeLedgerId','') is null
      or nullif(v_basis->>'senderPersonId','') is null
      or coalesce(v_basis->>'authorizationBasis','')<>'active_mutual_native_ledger_connections'
    then raise exception 'Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         (v_basis->>'senderPersonId')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
          and rel.attribution_state='active' and rel.evidence_kind='participant_attested'
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           and w.metadata->>'createdByPersonId'=v_basis->>'senderPersonId'
           and w.metadata->>'recipientPersonId'=new.assignee_canonical_person_id::text)
    then raise exception 'Connection-direct responsibility has no verified original Person and Ledger' using errcode='23514';end if;
    return new;
  end if;

  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id is not distinct from new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- Native Ledger standing agreement: canonical Person is the assignee,
  -- without invented Organization/employee membership. The original
  -- membership-based delegated branch below remains unchanged.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
      or (tg_op='INSERT' and new.assigned_by_membership_id is not null)
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'scopeId','') is null
      or nullif(v_basis->>'nativeLedgerId','') is null then
       raise exception 'Exact canonical Person standing-scope provenance required'
         using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_standing_assignment_scopes s
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=s.organization_id
      -- Native governing authority belongs to the verified Principal,
      -- not an Organization Membership/role label.
      join atlas.principals issuer
        on issuer.person_id=s.proposed_by_person_id
        and issuer.status='active'
      join atlas.principal_ledger_authorities grantor
        on grantor.principal_id=issuer.id and grantor.ledger_id=s.ledger_id
        and grantor.authority_kind='root_governing'
        and grantor.status='active'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
        and relevance.organization_id=s.organization_id
        and relevance.ledger_id=s.ledger_id
      where s.id::text=v_basis->>'scopeId'
        and (
          s.proposed_by_person_id=atlas.current_person_id_v1()
          OR (v_source='standing_continuing_source_admission_v1'
            AND atlas.current_person_id_v1()=s.worker_person_id
            AND EXISTS (
              SELECT 1 FROM atlas.continuing_work_source_governance_events_v1 policy
              JOIN atlas.rhythm_state rhythm
                ON rhythm.id=policy.source_id
                AND rhythm.organization_id=policy.organization_id
              JOIN atlas.work_items admitted
                ON admitted.id=new.work_item_id
                AND admitted.organization_id=policy.organization_id
              WHERE policy.id::text=admitted.metadata->>'standingPolicyEventId'
                AND policy.ledger_id=s.ledger_id
                AND policy.worker_scope_id=s.id
                AND policy.authorization_method='standing_source_observed'
                AND policy.id=(SELECT latest.id
                  FROM atlas.continuing_work_source_governance_events_v1 latest
                  WHERE latest.organization_id=policy.organization_id
                    AND latest.ledger_id=policy.ledger_id
                    AND latest.source_kind=policy.source_kind
                    AND latest.source_id=policy.source_id
                  ORDER BY latest.recorded_at DESC, latest.id DESC LIMIT 1)
                AND admitted.source_object_type='rhythm_state'
                AND admitted.source_object_id=rhythm.id
                AND admitted.metadata->>'sourceContract'='continuing_original_work_v1'
                AND admitted.metadata->>'standingAdmissionActorId'=s.worker_person_id::text
                AND admitted.metadata->>'sourceScopeId'=s.id::text
            ))
        )
        and s.organization_id=new.organization_id
        and s.ledger_id::text=v_basis->>'nativeLedgerId'
        and s.worker_person_id=new.assignee_canonical_person_id
        and s.worker_membership_id is null
        and s.scope_state='active' and s.accepted_at is not null
        and s.accepted_by_person_id=new.assignee_canonical_person_id
        and (s.valid_until is null or s.valid_until>now())
        and (s.coverage_mode='ledger_all_work' OR
          (s.coverage_mode='operation_class' AND
           work.organization_unit_id=s.organization_unit_id AND
           work.operation_class=s.covered_operation_class) OR
          -- Exact-Work is a third source-bound match, never a class/text grant.
          (s.coverage_mode='exact_work' AND
           s.covered_work_item_id IS NOT NULL AND
           s.covered_work_item_id=work.id))
        and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              work.id,s.ledger_id) proof
            where proof.source_schema=relevance.source_schema
              and proof.source_table=relevance.source_table
              and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Accepted canonical Person standing scope is not current for exact Work'
         using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
      new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
      new.assignee_canonical_person_id) then
      raise exception 'Canonical responsible Person no longer connected to this Ledger'
        using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$;


-- SOURCE QUALIFIED ONE WORK ADMISSION
-- HELD SOURCE ADMISSION, NOT A FARM TASK ENGINE.
-- An explicitly entrusted Person may admit exactly one native original Work
-- for a currently due, observed and disclosed Need under the Ledger owner's
-- immutable standing authorization. Work and day are explicit in this call.
-- No synthetic owner session, employee seat, clock-triggered work, or copied
-- physical observation. Built on native Work, Ledger, allocation, plan, Today.
CREATE OR REPLACE FUNCTION atlas.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_action_id uuid,p_service_date date
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $admit$
DECLARE
 v_actor uuid:=atlas.current_person_id_v1();
 v_policy atlas.continuing_work_source_governance_events_v1%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_state atlas.rhythm_state%ROWTYPE;
 v_rule atlas.rhythm_rules%ROWTYPE;
 v_object atlas.growing_objects%ROWTYPE;
 v_current atlas.care_current_state%ROWTYPE;
 v_observation atlas.care_observation_events%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_allocation uuid;
 v_plan uuid;
 v_stable text;
 v_eligibility jsonb;
 v_today date;
 v_title text;
 v_instructions text;
BEGIN
 IF auth.uid() IS NULL OR v_actor IS NULL OR p_organization_id IS NULL
 OR p_ledger_id IS NULL OR p_rhythm_state_id IS NULL
 OR p_action_id IS NULL OR p_service_date IS NULL
 THEN
  RAISE EXCEPTION 'Signed exact source and deliberate Person-day required'
   USING ERRCODE='22023';
 END IF;
 -- Lock physical observation -> source Need -> canonical serving. Signed
 -- concurrent reports and admission cannot mint two valid original servings.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.standing-physical-observation:'||p_organization_id||':'||p_rhythm_state_id,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-need-owner:'||p_organization_id||':'||p_rhythm_state_id,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
   'atlas.continuing-work:organization:'||p_organization_id||
   ':rhythm_state:'||p_rhythm_state_id,0));
 SELECT * INTO v_policy FROM atlas.continuing_work_source_governance_events_v1 p
 WHERE p.organization_id=p_organization_id AND p.ledger_id=p_ledger_id
 AND p.source_kind='rhythm_state' AND p.source_id=p_rhythm_state_id
 ORDER BY p.recorded_at DESC,p.id DESC LIMIT 1;
 IF v_policy.id IS NULL OR v_policy.authorization_method<>'standing_source_observed'
 OR v_policy.worker_visibility<>'eligible_disclosed' THEN
   RAISE EXCEPTION 'No current governor-authorized standing admission'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.id=v_policy.worker_scope_id AND s.organization_id=p_organization_id
 AND s.ledger_id=p_ledger_id FOR SHARE;
 IF v_scope.id IS NULL OR v_scope.proposed_by_person_id IS DISTINCT FROM
   v_policy.decided_by_person_id
 OR v_scope.worker_person_id IS DISTINCT FROM v_actor
 OR v_scope.worker_membership_id IS NOT NULL
 OR v_scope.scope_state<>'active' OR v_scope.coverage_mode<>'ledger_all_work'
 OR v_scope.accepted_at IS NULL
 OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
 OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_actor)
 OR NOT EXISTS (
   SELECT 1 FROM atlas.principals principal
   JOIN atlas.principal_ledger_authorities a ON a.principal_id=principal.id
   WHERE principal.person_id=v_policy.decided_by_person_id
    AND principal.status='active' AND a.ledger_id=p_ledger_id
    AND a.authority_kind='root_governing' AND a.status='active')
 THEN
   RAISE EXCEPTION 'Current owner mandate and accepted connected Person required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
 AND s.subject_kind='growing_object' FOR UPDATE;
 SELECT * INTO v_rule FROM atlas.rhythm_rules r
 JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
 WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
 AND b.farm_id=v_state.farm_id AND b.organization_id=p_organization_id
 AND b.active AND r.status='active';
 SELECT * INTO v_object FROM atlas.growing_objects g
 WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id;
 IF v_state.id IS NULL OR v_rule.id IS NULL OR v_object.id IS NULL
 OR v_state.state='paused'
 OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
 OR NOT EXISTS(SELECT 1 FROM atlas.farms f
   WHERE f.id=v_state.farm_id AND f.organization_id=p_organization_id
   AND f.status='active')
 THEN RAISE EXCEPTION 'Current physical governing source unavailable'
   USING ERRCODE='23514'; END IF;
 IF NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'identity')
 OR NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_actor,'spatial','growing_object',v_state.subject_id,'condition')
 THEN RAISE EXCEPTION 'Standing Work physical Subject withheld'
   USING ERRCODE='42501'; END IF;
 v_today:=(now() AT TIME ZONE
   coalesce(nullif(v_rule.metadata->>'timezoneName',''),'UTC'))::date;
 IF p_service_date<v_today OR p_service_date>v_today+14 THEN
   RAISE EXCEPTION 'Worker-selected source Work service day must be within the next 14 local days'
   USING ERRCODE='22023'; END IF;
 v_stable:='continuing:v1:'||md5(
   'organization:'||p_organization_id||':rhythm_state:'||p_rhythm_state_id
   ||':'||p_action_id);
 -- Exact retry preserves Work and plan history. Never shift the assigned
 -- day or source authority as a side-effect of an idempotency retry.
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.organization_id=p_organization_id
 AND w.stable_key=v_stable AND w.source_object_type='rhythm_state'
 AND w.source_object_id=p_rhythm_state_id FOR UPDATE;
 IF v_work.id IS NOT NULL THEN
   IF v_work.metadata->>'standingPolicyEventId' IS DISTINCT FROM v_policy.id::text
   OR v_work.metadata->>'sourceScopeId' IS DISTINCT FROM v_scope.id::text
   OR v_work.metadata->>'sourceServiceDate' IS DISTINCT FROM p_service_date::text
   OR v_work.metadata->>'standingAdmissionActorId' IS DISTINCT FROM v_actor::text
   THEN RAISE EXCEPTION 'Standing action replay would change original Work'
    USING ERRCODE='23505'; END IF;
   RETURN jsonb_build_object('ok',true,'idempotent',true,
     'workItemId',v_work.id,'workState',v_work.work_state,
     'noNewWorkCreated',true,'assignmentUnchanged',true);
 END IF;
 -- NO second serving while the prior original or legacy obligation is open.
 IF EXISTS (SELECT 1 FROM atlas.work_items w
    WHERE w.organization_id=p_organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=p_rhythm_state_id AND w.work_state='open')
 OR EXISTS (SELECT 1 FROM atlas.tasks t
    LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
    WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
    AND (t.metadata->>'rhythm_state_id'=p_rhythm_state_id::text
       OR (o.source_kind='rhythm_state' AND o.source_id=p_rhythm_state_id)))
 THEN RAISE EXCEPTION 'Existing original or legacy Work still serves this Need'
    USING ERRCODE='23514'; END IF;
 -- Reuse the existing signed source evaluator: due clock alone never admits.
 v_eligibility:=atlas.continuing_work_source_eligibility_self_api_v1(
    p_organization_id,p_ledger_id,p_rhythm_state_id);
 IF v_eligibility->>'eligible' IS DISTINCT FROM 'true'
 OR v_eligibility->>'reasonCode' IS DISTINCT FROM 'source_qualified_and_timing_eligible'
 THEN RAISE EXCEPTION 'Current observed source is not eligible for new Work'
    USING ERRCODE='23514'; END IF;
 SELECT * INTO v_current FROM atlas.care_current_state c
 WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
  AND c.subject_domain='farm' AND c.subject_kind='growing_object'
  AND c.subject_id=v_state.subject_id::text FOR SHARE;
 SELECT * INTO v_observation FROM atlas.care_observation_events e
 WHERE e.id=v_current.last_observation_id AND e.scope_id=v_state.farm_id
  AND e.subject_kind='growing_object' AND e.subject_id=v_state.subject_id::text;
 IF v_observation.id IS NULL OR v_observation.inferred_from_clock
 OR v_observation.observed_by_user_id IS NULL
 OR v_observation.condition_state IS DISTINCT FROM v_current.condition_state
 OR v_current.last_observed_at IS DISTINCT FROM v_observation.observed_at
 OR v_observation.observed_at < now()-(
     v_policy.observation_max_age_seconds * interval '1 second')
 OR v_observation.observed_at <= COALESCE(
   (SELECT satisfaction.satisfied_at FROM atlas.rhythm_satisfactions satisfaction
    WHERE satisfaction.id=v_state.last_qualifying_satisfaction_id),
   '-infinity'::timestamptz)
 THEN RAISE EXCEPTION 'Fresh source condition changed; review again'
  USING ERRCODE='23514'; END IF;
 IF v_state.rhythm_key='mowing' THEN
   v_title:='Inspect and mow if warranted — '||v_object.label;
   v_instructions:='Inspect route and ground safety. Mow only if appropriate and report the physical result.';
 ELSE
   v_title:='Inspect and weed if warranted — '||v_object.label;
   v_instructions:='Inspect weed pressure and care strategy. Weed only if warranted and report actual condition.';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies p
   WHERE p.contract_key='continuing_care_actual_v1' AND p.active
     AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
     AND p.metadata->>'continuingActualQualification'='source_proven_v1')
 THEN RAISE EXCEPTION 'Native physical Result contract unavailable'
   USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.work_items (
   organization_id,title,instructions,work_state,
   source_object_type,source_object_id,stable_key,result_contract_key,
   created_by_user_id,metadata
 ) VALUES(
   p_organization_id,left(v_title,500),v_instructions,'open',
   'rhythm_state',p_rhythm_state_id,v_stable,'continuing_care_actual_v1',
   auth.uid(),
   jsonb_build_object(
     'sourceContract','continuing_original_work_v1',
     'needKind','rhythm_state','needId',p_rhythm_state_id,
     'servingKey',p_action_id,
     'sourceConfirmedBy','standing_source_observed_with_signed_physical_evidence',
     'standingPolicyEventId',v_policy.id,
     'sourceScopeId',v_scope.id,
     'sourceServiceDate',p_service_date,
     'sourceObservationId',v_observation.id,
     'sourceObservedAt',v_observation.observed_at,
     'sourceObservedCondition',v_observation.condition_state,
     'standingAdmissionActorId',v_actor,
     'noCalendarDateInferred',true,'noClockAdmissionInferred',true)
 ) RETURNING * INTO v_work;
 INSERT INTO atlas.work_item_context_links(
   organization_id,work_item_id,subject_domain,
   subject_kind,subject_id,relation_kind,provenance,metadata
 ) VALUES(
   p_organization_id,v_work.id,'spatial','growing_object',
   v_state.subject_id,'acts_on',
   jsonb_build_object('needKind','rhythm_state','needId',p_rhythm_state_id,
     'sourceContract','continuing_original_work_v1',
     'standingPolicyEventId',v_policy.id,'sourceObservationId',v_observation.id),
   '{}'::jsonb);
 -- Source verified, NOT a false new governor attestation. The trusted
 -- exact-source resolver must return this immutable owner policy event.
 INSERT INTO atlas.company_work_native_ledger_relevance(
   organization_id,work_item_id,ledger_id,evidence_kind,
   source_schema,source_table,source_id,verified_at,established_by_person_id
 ) VALUES(
   p_organization_id,v_work.id,p_ledger_id,'source_verified',
   'atlas','continuing_work_source_governance_events_v1',v_policy.id,
   clock_timestamp(),v_actor);
 IF NOT EXISTS(SELECT 1
    FROM atlas.company_work_native_ledger_exact_source_v1(v_work.id,p_ledger_id) source
    WHERE source.source_schema='atlas'
      AND source.source_table='continuing_work_source_governance_events_v1'
      AND source.source_id=v_policy.id)
 THEN RAISE EXCEPTION 'Existing native Work Ledger source resolver rejected standing authority'
  USING ERRCODE='23514'; END IF;
 INSERT INTO atlas.work_allocations(
   organization_id,work_item_id,assignee_membership_id,
   assignee_canonical_person_id,assigned_by_membership_id,
   allocation_role,state,allocated_at,establishment_basis_kind,
   establishment_basis,metadata
 ) VALUES(
   p_organization_id,v_work.id,NULL,v_scope.worker_person_id,NULL,
   'responsible','active',clock_timestamp(),
   'delegated_under_standing_scope',
   jsonb_build_object('contractVersion','exact_work_responsibility_establishment_v2',
     'basisKind','delegated_under_standing_scope',
     'organizationId',p_organization_id,'workItemId',v_work.id,
     'nativeLedgerId',p_ledger_id,'scopeId',v_scope.id,
     'assigneePersonId',v_scope.worker_person_id,
     'scopeAcceptedAt',v_scope.accepted_at,'establishedAt',clock_timestamp(),
     'standingPolicyEventId',v_policy.id,
     'physicalSourceObservationId',v_observation.id),
   jsonb_build_object('source','standing_continuing_source_admission_v1',
     'governorPersonId',v_policy.decided_by_person_id,
     'admittedByPersonId',v_actor,'noEmployeeSeatRequired',true)
 ) RETURNING id INTO v_allocation;
 INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,
    plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata
 ) VALUES(
    p_organization_id,v_work.id,v_allocation,NULL,NULL,
    'active',p_service_date,p_service_date,p_service_date,
    'Connected Person explicitly selected this service day under preauthorized, physically verified standing care.',
    jsonb_build_object('source','standing_continuing_source_admission_v1',
       'governorPolicyEventId',v_policy.id,
       'physicalObservationId',v_observation.id,
       'personSelectedDay',true,'noClockPlacement',true)
 ) RETURNING id INTO v_plan;
 INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
 ) VALUES(
   p_organization_id,v_work.id,v_plan,'planned',
   p_service_date,p_service_date,NULL,
   'Original Work date explicitly selected by signed entrusted Person within owner mandate',
   jsonb_build_object('standingPolicyEventId',v_policy.id,
       'sourceObservationId',v_observation.id,'workerPersonId',v_actor));
 RETURN jsonb_build_object('ok',true,'contractVersion',
    'standing_continuing_original_work_admission_v1',
    'workItemId',v_work.id,'rhythmStateId',p_rhythm_state_id,
    'responsiblePersonId',v_actor,'policyEventId',v_policy.id,
    'physicalObservationId',v_observation.id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,'newOriginalWorkCreated',true,
    'noNextWorkPrecreated',true,'noClockAdmission',true);
END;
$admit$;
REVOKE ALL ON FUNCTION atlas.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,
 p_action_id uuid,p_service_date date
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.admit_standing_continuing_source_work_self_api_v1(
 p_organization_id,p_ledger_id,p_rhythm_state_id,p_action_id,p_service_date);
$public$;
REVOKE ALL ON FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_standing_continuing_source_work_self_api_v1(
 uuid,uuid,uuid,uuid,date
) TO authenticated;
SELECT pg_catalog.pg_notify('pgrst','reload schema');


-- NATIVE SOURCE ADMISSION POSTCONDITIONS
-- HELD: stand-alone source checks on the original native Work architecture.
DO $admission_gate$
DECLARE
 v_internal regprocedure:=to_regprocedure('atlas.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)');
 v_public regprocedure:=to_regprocedure('public.admit_standing_continuing_source_work_self_api_v1(uuid,uuid,uuid,uuid,date)');
 v_source regprocedure:=to_regprocedure('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)');
 v_native regprocedure:=to_regprocedure('atlas.guard_work_allocation_responsibility_establishment_v2()');
 v_sql text;
BEGIN
 IF v_internal IS NULL OR v_public IS NULL OR v_source IS NULL OR v_native IS NULL
 THEN RAISE EXCEPTION 'Exact native standing Work admission source missing'; END IF;
 IF has_function_privilege('anon',v_public,'EXECUTE')
 OR has_function_privilege('anon',v_internal,'EXECUTE')
 OR has_function_privilege('authenticated',v_internal,'EXECUTE')
 OR has_function_privilege('service_role',v_internal,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
 THEN RAISE EXCEPTION 'Client may bypass signed standing source membrane'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p
   WHERE p.oid=v_internal AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig))
 THEN RAISE EXCEPTION 'Standing source admission must use empty pinned search path'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint con
    WHERE con.conrelid='atlas.company_work_native_ledger_relevance'::regclass
    AND con.conname='company_work_relevance_evidence_separation_v1'
    AND position('continuing_work_source_governance_events_v1' IN pg_get_constraintdef(con.oid))>0)
 THEN RAISE EXCEPTION 'Standing source must have bounded, verified Ledger relevance'; END IF;
 v_sql:=pg_get_functiondef(v_source);
 IF position('booking_requests' IN v_sql)=0
 OR position('booking_offerings' IN v_sql)=0
 OR position('continuing_work_source_governance_events_v1' IN v_sql)=0
 THEN RAISE EXCEPTION 'Native Ledger exact source lost existing or new proof'; END IF;
 v_sql:=pg_get_functiondef(v_native);
 IF position('standing_continuing_source_admission_v1' IN v_sql)=0
 OR position('standingPolicyEventId' IN v_sql)=0
 OR position('delegated_under_standing_scope' IN v_sql)=0
 THEN RAISE EXCEPTION 'Current native responsibility trigger lacks exact standing authorization'; END IF;
 v_sql:=pg_get_functiondef(v_internal);
 IF position('source_qualified_and_timing_eligible' IN v_sql)=0
 OR position('has_current_subject_disclosure_v1' IN v_sql)=0
 OR position('continuing-work:organization:' IN v_sql)=0
 OR position('existing original or legacy work' IN lower(v_sql))=0
 OR position('care_current_state' IN v_sql)=0
 OR position('source_verified' IN v_sql)=0
 OR position('work_execution_plans' IN v_sql)=0
 OR position('noClockAdmission' IN v_sql)=0
 THEN RAISE EXCEPTION 'Standing admission source lacks current Work/physical/Person-day guard'; END IF;
 RAISE NOTICE 'One canonical original Work, one Person allocation and a deliberately selected service day remain source-gated.';
END;
$admission_gate$;

-- Signed disclosed-care list: extra held source under existing clone-only canary.
-- HELD SOURCE-ONLY candidate stacked on Noel #2362.
-- Discover ONLY a signed native Person's explicitly disclosed standing care
-- expectations. A cadence is not an original Work, deadline or overdue task.
CREATE OR REPLACE FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit integer DEFAULT 30,
 p_after_state_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $rhythms$
DECLARE
 v_person uuid;
 v_items jsonb := '[]'::jsonb;
 v_has_more boolean := false;
 v_last uuid;
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
   OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
   RAISE EXCEPTION 'Signed bounded Ledger source required' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL THEN
   RAISE EXCEPTION 'Current native Person required' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_person) THEN
   RAISE EXCEPTION 'Exact native Ledger connection required' USING ERRCODE='42501';
 END IF;

 WITH admitted AS MATERIALIZED (
   SELECT s.id state_id,s.rhythm_key rhythm_kind,
     g.label subject_label,r.label rhythm_label,
     r.validity_interval_seconds cadence_seconds,s.warning_at,s.due_at
   FROM atlas.rhythm_state s
   JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
     AND b.rhythm_rule_id=s.rhythm_rule_id AND b.active
     AND b.organization_id=p_organization_id AND b.farm_id=s.farm_id
   JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
     AND r.organization_id=p_organization_id AND r.status='active'
   JOIN atlas.farms f ON f.id=s.farm_id
     AND f.organization_id=p_organization_id AND f.status='active'
   JOIN atlas.growing_objects g ON g.id=s.subject_id AND g.farm_id=s.farm_id
   JOIN LATERAL (
     SELECT e.* FROM atlas.continuing_work_source_governance_events_v1 e
     WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
       AND e.source_kind='rhythm_state' AND e.source_id=s.id
     ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
   ) policy ON TRUE
   JOIN atlas.company_work_standing_assignment_scopes scope
     ON scope.id=policy.worker_scope_id
     AND scope.organization_id=p_organization_id
     AND scope.ledger_id=p_ledger_id AND scope.worker_person_id=v_person
   WHERE s.organization_id=p_organization_id
     AND s.subject_kind='growing_object'
     AND s.rhythm_key IN ('mowing','weed_stewardship')
     AND s.state <> 'paused'
     AND (p_after_state_id IS NULL OR s.id>p_after_state_id)
     AND policy.authorization_method='standing_source_observed'
     AND policy.worker_visibility='eligible_disclosed'
     AND scope.scope_state='active'
     AND scope.accepted_at IS NOT NULL
     AND scope.accepted_by_person_id=v_person
     AND scope.worker_membership_id IS NULL
     AND scope.coverage_mode='ledger_all_work'
     AND (scope.valid_until IS NULL OR scope.valid_until>now())
     AND atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,'spatial','growing_object',s.subject_id,'identity')
     AND atlas.has_current_subject_disclosure_v1(
       p_ledger_id,v_person,'spatial','growing_object',s.subject_id,'condition')
   ORDER BY s.id
   LIMIT (p_limit+1)
 ), numbered AS (
   SELECT admitted.*,row_number() over(ORDER BY state_id) ordinal
   FROM admitted
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'rhythmStateId',state_id,'rhythmKind',rhythm_kind,
   'rhythmLabel',rhythm_label,'subjectLabel',subject_label,
   'cadenceSeconds',cadence_seconds,'cadenceWarningAt',warning_at,
   'cadenceDueAt',due_at,'isWork',false,'isAssignment',false
 ) ORDER BY state_id) FILTER(WHERE ordinal<=p_limit),'[]'::jsonb),
 count(*)>p_limit,(max(state_id::text) FILTER(WHERE ordinal<=p_limit))::uuid
 INTO v_items,v_has_more,v_last FROM numbered;

 RETURN jsonb_build_object(
   'ok',true,'contractVersion','connected_person_disclosed_standing_rhythms_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'items',v_items,'hasMore',v_has_more,
   'nextAfterStateId',CASE WHEN v_has_more THEN v_last ELSE NULL END,
   'coverage','admitted_person_only','noUndisclosedCounts',true,
   'noWorkCreated',true,'notAnExecutionPlan',true,
   'notAnAutomaticOverdueBacklog',true);
END;
$rhythms$;
REVOKE ALL ON FUNCTION atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_limit integer DEFAULT 30,
 p_after_state_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $public$
 SELECT atlas.connected_person_disclosed_standing_rhythms_self_api_v1(
   p_organization_id,p_ledger_id,p_limit,p_after_state_id);
$public$;
REVOKE ALL ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.connected_person_disclosed_standing_rhythms_self_api_v1(
 uuid,uuid,integer,uuid) TO authenticated;


-- DELIBERATELY OVERRIDE OLD CLONE-ONLY AUTHORITY WITH CURRENT NATIVE-ONLY HELD SOURCE
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

-- HELD / owner decision #2392. This is an immutable review of historical
-- source, never another Work engine, accepted Actual or legacy authorization.
CREATE TABLE atlas.historical_self_adoption_review_events_v1(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 ledger_id uuid NOT NULL,
 work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 allocation_id uuid NOT NULL REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT,
 event_kind text NOT NULL CHECK(event_kind IN ('person_confirmed','worker_pending','governor_reviewed')),
 action_id uuid NOT NULL,
 actor_person_id uuid NOT NULL REFERENCES reality.entities(id),
 linked_person_id uuid REFERENCES reality.entities(id),
 parent_event_id uuid REFERENCES atlas.historical_self_adoption_review_events_v1(id),
 evidence_event_id uuid REFERENCES atlas.historical_self_adoption_review_events_v1(id),
 outcome text CHECK(outcome IN ('historically_performed','obsolete_cancelled','still_unresolved')),
 evidence_text text CHECK(evidence_text IS NULL OR length(evidence_text)<=2000),
 snapshot jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(snapshot)='object'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(ledger_id,action_id),
 CHECK (
  (event_kind='person_confirmed' AND linked_person_id IS NOT NULL AND parent_event_id IS NULL AND outcome IS NULL)
  OR (event_kind='worker_pending' AND parent_event_id IS NOT NULL AND linked_person_id=actor_person_id
     AND nullif(btrim(evidence_text),'') IS NOT NULL AND outcome IS NULL)
  OR (event_kind='governor_reviewed' AND parent_event_id IS NOT NULL AND outcome IS NOT NULL AND linked_person_id IS NULL)
 )
);
CREATE UNIQUE INDEX historical_self_adoption_one_person_link_v1
 ON atlas.historical_self_adoption_review_events_v1(organization_id,ledger_id,allocation_id)
 WHERE event_kind='person_confirmed';
CREATE UNIQUE INDEX historical_self_adoption_one_review_v1
 ON atlas.historical_self_adoption_review_events_v1(parent_event_id)
 WHERE event_kind='governor_reviewed';
CREATE INDEX historical_self_adoption_work_read_v1
 ON atlas.historical_self_adoption_review_events_v1(ledger_id,work_item_id,recorded_at,id);
ALTER TABLE atlas.historical_self_adoption_review_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.historical_self_adoption_review_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.historical_self_adoption_review_events_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION atlas.reject_historical_review_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $imm$ BEGIN RAISE EXCEPTION 'Historical review is immutable' USING ERRCODE='42501'; END; $imm$;
CREATE TRIGGER reject_historical_review_mutation_v1 BEFORE UPDATE OR DELETE
 ON atlas.historical_self_adoption_review_events_v1 FOR EACH ROW
 EXECUTE FUNCTION atlas.reject_historical_review_mutation_v1();
REVOKE ALL ON FUNCTION atlas.reject_historical_review_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Exact native governor confirms a historical Person link without assigning
-- current Work, granting visibility, changing a result, or creating a new Work.
CREATE OR REPLACE FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_allocation_id uuid,
 p_related_person_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $link$
DECLARE a uuid; e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_action_id IS NULL OR p_related_person_id IS NULL OR p_work_item_id IS NULL OR p_allocation_id IS NULL
 THEN RAISE EXCEPTION 'Exact historical identity and action required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('history-link:'||p_allocation_id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
  WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'person_confirmed' OR e.actor_person_id IS DISTINCT FROM a
    OR e.work_item_id IS DISTINCT FROM p_work_item_id
    OR e.allocation_id IS DISTINCT FROM p_allocation_id
    OR e.linked_person_id IS DISTINCT FROM p_related_person_id
  THEN RAISE EXCEPTION 'Conflicting historical link replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'linkId',e.id,'historicalOnly',true,'replay',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_items w
    JOIN atlas.work_allocations x ON x.work_item_id=w.id
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND x.id=p_allocation_id AND x.organization_id=p_organization_id
      AND x.establishment_basis_kind='self_adoption')
 OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
      AND r.work_item_id=p_work_item_id AND r.attribution_state='active')
 OR NOT EXISTS(SELECT 1 FROM reality.entities p WHERE p.id=p_related_person_id
    AND p.entity_kind='person' AND p.identity_state='canonical')
 THEN RAISE EXCEPTION 'Exact governed historical Work/Person source required' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 h
   WHERE h.ledger_id=p_ledger_id AND h.allocation_id=p_allocation_id
      AND h.event_kind='person_confirmed')
 THEN RAISE EXCEPTION 'Conflicting historical Person; correction requires adjudication'
 USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
   organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
   actor_person_id,linked_person_id,snapshot)
 VALUES (p_organization_id,p_ledger_id,p_work_item_id,p_allocation_id,'person_confirmed',
   p_action_id,a,p_related_person_id,
   jsonb_build_object('nativeGovernorConfirmed',true,'legacyAuthorityGranted',false,
     'newWorkCreated',false,'currentAssignmentCreated',false))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'linkId',e.id,'historicalOnly',true,
   'newWorkCreated',false,'newAuthorityGranted',false,'replay',false);
END; $link$;

-- Worker report is pending evidence, NOT Done, and requires currently signed,
-- connected canonical Person and source-enforced original Work disclosure.
CREATE OR REPLACE FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_evidence_text text,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $pending$
DECLARE a uuid:=atlas.current_person_id_v1();
 l atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR a IS NULL
   OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed current native Person required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
 IF p_link_id IS NULL OR p_action_id IS NULL
    OR nullif(btrim(coalesce(p_evidence_text,'')),'') IS NULL OR length(p_evidence_text)>2000
 THEN RAISE EXCEPTION 'Actual historical report and action required' USING ERRCODE='22023'; END IF;
 SELECT * INTO l FROM atlas.historical_self_adoption_review_events_v1
 WHERE id=p_link_id AND organization_id=p_organization_id AND ledger_id=p_ledger_id
   AND event_kind='person_confirmed' AND linked_person_id=a;
 IF l.id IS NULL
   OR NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,a)
   OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
       WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
         AND r.work_item_id=l.work_item_id AND r.attribution_state='active')
   OR NOT atlas.person_original_work_identity_disclosed_self_v1(
     p_organization_id,p_ledger_id,l.work_item_id,a)
 THEN RAISE EXCEPTION 'Historical source not disclosed to current Person' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 d
   WHERE d.parent_event_id=l.id AND d.event_kind='governor_reviewed')
 THEN RAISE EXCEPTION 'Historical review already finalized; new evidence needs a governed reopen'
 USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('historical-evidence:'||p_action_id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
 WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'worker_pending' OR e.parent_event_id IS DISTINCT FROM l.id
     OR e.actor_person_id IS DISTINCT FROM a OR e.evidence_text IS DISTINCT FROM btrim(p_evidence_text)
  THEN RAISE EXCEPTION 'Conflicting historical evidence replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'evidenceId',e.id,'state','pending','acceptedDone',false,'replay',true);
 END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
 organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
 actor_person_id,linked_person_id,parent_event_id,evidence_text,snapshot)
 VALUES(p_organization_id,p_ledger_id,l.work_item_id,l.allocation_id,'worker_pending',
 p_action_id,a,a,l.id,btrim(p_evidence_text),
 jsonb_build_object('newResultCreated',false,'acceptedDone',false,'originalWorkUnchanged',true))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'evidenceId',e.id,'state','pending','acceptedDone',false,'replay',false);
END; $pending$;

-- Owner historical decision is audit evidence and deliberately cannot alter
-- the original Work state. The eventual lifecycle closure must be a
-- separately admitted native transition, not hidden inside a review event.
CREATE OR REPLACE FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_outcome text,
 p_evidence_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE a uuid; l atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 e atlas.historical_self_adoption_review_events_v1%ROWTYPE;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_action_id IS NULL OR p_link_id IS NULL
 OR p_outcome IS NULL OR p_outcome NOT IN
 ('historically_performed','obsolete_cancelled','still_unresolved')
 THEN RAISE EXCEPTION 'Exact review outcome and action required' USING ERRCODE='22023'; END IF;
 SELECT * INTO l FROM atlas.historical_self_adoption_review_events_v1
 WHERE id=p_link_id AND organization_id=p_organization_id AND ledger_id=p_ledger_id
 AND event_kind='person_confirmed';
 IF l.id IS NULL OR NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance r
   WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.work_item_id=l.work_item_id AND r.attribution_state='active')
 THEN RAISE EXCEPTION 'Exact governed historical source required' USING ERRCODE='42501'; END IF;
 IF p_evidence_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 p
   WHERE p.id=p_evidence_id AND p.parent_event_id=l.id
   AND p.event_kind='worker_pending' AND p.ledger_id=p_ledger_id)
 THEN RAISE EXCEPTION 'Wrong historical evidence reference' USING ERRCODE='42501'; END IF;
 IF p_outcome='obsolete_cancelled' AND EXISTS (
   SELECT 1 FROM atlas.work_execution_results r
   JOIN atlas.work_result_acceptances c ON c.execution_result_id=r.id
   WHERE r.work_item_id=l.work_item_id AND r.responsible_allocation_id=l.allocation_id
   AND c.decision='accepted' AND c.work_item_id=r.work_item_id
 ) THEN RAISE EXCEPTION 'Accepted historical performance cannot be reclassified as obsolete'
 USING ERRCODE='23514'; END IF;
 IF p_outcome='historically_performed' AND p_evidence_id IS NULL
 AND NOT EXISTS(SELECT 1 FROM atlas.work_execution_results r
   JOIN atlas.work_result_acceptances c ON c.execution_result_id=r.id
   WHERE r.work_item_id=l.work_item_id AND r.responsible_allocation_id=l.allocation_id
   AND c.decision='accepted' AND c.work_item_id=r.work_item_id)
 THEN RAISE EXCEPTION 'Historical performance requires actual evidence' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('historical-review:'||l.id::text,0));
 SELECT * INTO e FROM atlas.historical_self_adoption_review_events_v1
 WHERE ledger_id=p_ledger_id AND action_id=p_action_id;
 IF e.id IS NOT NULL THEN
  IF e.event_kind<>'governor_reviewed' OR e.parent_event_id IS DISTINCT FROM l.id
  OR e.actor_person_id IS DISTINCT FROM a OR e.outcome IS DISTINCT FROM p_outcome
  OR e.evidence_event_id IS DISTINCT FROM p_evidence_id
  THEN RAISE EXCEPTION 'Conflicting historical review replay' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'reviewId',e.id,'outcome',e.outcome,'workStateChanged',false,'replay',true);
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.historical_self_adoption_review_events_v1 r
    WHERE r.parent_event_id=l.id AND r.event_kind='governor_reviewed')
 THEN RAISE EXCEPTION 'Historical decision already reviewed; correction requires adjudication'
 USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.historical_self_adoption_review_events_v1(
 organization_id,ledger_id,work_item_id,allocation_id,event_kind,action_id,
 actor_person_id,parent_event_id,evidence_event_id,outcome,snapshot)
 VALUES(p_organization_id,p_ledger_id,l.work_item_id,l.allocation_id,'governor_reviewed',
 p_action_id,a,l.id,p_evidence_id,p_outcome,
 jsonb_build_object('originalWorkUnchanged',true,'noAcceptedActualFabricated',true))
 RETURNING * INTO e;
 RETURN jsonb_build_object('ok',true,'reviewId',e.id,'outcome',p_outcome,
 'historicalOnly',true,'workStateChanged',false,'replay',false);
END; $review$;

REVOKE ALL ON FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 TO authenticated;

-- HELD source-only readback; exact governor Ledger authority, no worker leak.
-- Readback is bounded; any omission is explicit. No raw table permission.
CREATE OR REPLACE FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $history$
DECLARE a uuid; v_rows jsonb:='[]'::jsonb; v_more boolean:=false;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_work_item_id IS NULL OR NOT EXISTS (
 SELECT 1 FROM atlas.work_items w
 JOIN atlas.company_work_native_ledger_relevance r ON r.work_item_id=w.id
 WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
   AND r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.attribution_state='active') THEN
 RAISE EXCEPTION 'Exact authorized historical source required' USING ERRCODE='42501';
 END IF;
 WITH ordered AS (
 SELECT e.*,row_number() OVER (ORDER BY e.recorded_at,e.id) AS seq
 FROM atlas.historical_self_adoption_review_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.work_item_id=p_work_item_id
 ORDER BY e.recorded_at,e.id LIMIT 51
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'id',id,'kind',event_kind,'historicalWorkId',work_item_id,
 'allocationId',allocation_id,'actorPersonId',actor_person_id,
 'linkedPersonId',linked_person_id,'parentId',parent_event_id,
 'evidenceId',evidence_event_id,'outcome',outcome,
 'evidenceText',evidence_text,'recordedAt',recorded_at)
 ORDER BY seq) FILTER(WHERE seq<=50),'[]'::jsonb),
 coalesce(bool_or(seq>50),false)
 INTO v_rows,v_more FROM ordered;
 RETURN jsonb_build_object('ok',true,'contractVersion','historical_self_adoption_history_v1',
 'sourceWorkItemId',p_work_item_id,'items',v_rows,'hasMore',v_more,
 'bounded',true,'authoritativeWorkStateChanged',false,'historicalOnly',true);
END; $history$;
REVOKE ALL ON FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 TO authenticated;

-- HELD source-only PostgREST transport; no raw historical table exposure.
-- Every internal writer independently requires the exact native governor
-- or signed current worker/Seat/Subject disclosure; PUBLIC and anon denied.
CREATE OR REPLACE FUNCTION public.governor_link_historical_self_adoption_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_allocation_id uuid,p_related_person_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_link_historical_self_adoption_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id,p_allocation_id,p_related_person_id,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.report_historical_self_adoption_pending_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_evidence_text text,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.report_historical_self_adoption_pending_self_api_v1(p_organization_id,p_ledger_id,p_link_id,p_evidence_text,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.governor_review_historical_self_adoption_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_outcome text,p_evidence_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_review_historical_self_adoption_self_api_v1(p_organization_id,p_ledger_id,p_link_id,p_outcome,p_evidence_id,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.governor_historical_self_adoption_history_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_historical_self_adoption_history_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid) TO authenticated;


-- native-governor historical retirement clone slice (source PR #2368).
-- The base clone installed the original singleton lifecycle and append-only
-- historical review; replace only its private function, preserving one ID.
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
   OR p_transition_kind NOT IN ('complete','cancel') THEN
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
 -- The only cancellation admitted in this draft is a *reviewed historical*
 -- self-adopted original.  This is not a general cancel API.  The
 -- p_result_id slot carries the immutable historical review event ONLY for
 -- transition_kind='cancel'; no physical Result or Acceptance is created.
 IF p_transition_kind='cancel' THEN
   DECLARE
     v_review record;
     v_link record;
     v_impact jsonb;
     v_at timestamptz;
     v_plan atlas.work_execution_plans%ROWTYPE;
   BEGIN
     SELECT * INTO v_review
     FROM atlas.historical_self_adoption_review_events_v1 h
     WHERE h.id=p_result_id AND h.work_item_id=v_work.id
       AND h.organization_id=v_work.organization_id
       AND h.event_kind='governor_reviewed'
       AND h.outcome='obsolete_cancelled';
     IF v_review.id IS NULL THEN
       RAISE EXCEPTION 'Exact obsolete historical review required for retirement'
         USING ERRCODE='42501';
     END IF;
     SELECT * INTO v_link
     FROM atlas.historical_self_adoption_review_events_v1 h
     WHERE h.id=v_review.parent_event_id
       AND h.event_kind='person_confirmed'
       AND h.ledger_id=v_review.ledger_id
       AND h.work_item_id=v_work.id
       AND h.organization_id=v_work.organization_id
       AND h.allocation_id=v_review.allocation_id;
     IF v_link.id IS NULL
       OR NOT EXISTS(
         SELECT 1 FROM atlas.company_work_native_ledger_relevance r
         WHERE r.organization_id=v_work.organization_id
           AND r.ledger_id=v_review.ledger_id
           AND r.work_item_id=v_work.id AND r.attribution_state='active')
       OR atlas.company_work_native_ledger_owner_self_v1(
           v_work.organization_id,v_review.ledger_id) IS DISTINCT FROM v_actor
       OR NOT EXISTS(
         SELECT 1 FROM atlas.work_allocations a
         WHERE a.id=v_review.allocation_id
           AND a.work_item_id=v_work.id
           AND a.organization_id=v_work.organization_id
           AND a.establishment_basis_kind='self_adoption')
     THEN RAISE EXCEPTION 'Present native Ledger governor and reviewed source required'
       USING ERRCODE='42501'; END IF;
     -- Replay retains the exact original review/actor/action and terminal
     -- projection.  A same-key completion or different reviewer conflicts.
     SELECT * INTO v_event
     FROM atlas.work_lifecycle_events_v1 e
     WHERE e.work_item_id=v_work.id
       AND e.event_kind='work_transition_applied'
       AND e.source_idempotency_key=v_key
     ORDER BY e.sequence_no DESC LIMIT 1;
     IF v_event.id IS NOT NULL THEN
       IF v_event.source_table IS DISTINCT FROM
             'atlas.historical_self_adoption_review_events_v1'
         OR v_event.source_row_id IS DISTINCT FROM v_review.id
         OR v_event.actor_user_id IS DISTINCT FROM v_uid
         OR v_event.from_state IS DISTINCT FROM 'open'
         OR v_event.to_state IS DISTINCT FROM 'cancelled'
         OR v_work.work_state IS DISTINCT FROM 'cancelled'
       THEN RAISE EXCEPTION 'Conflicting historical retirement replay'
          USING ERRCODE='23505'; END IF;
       RETURN jsonb_build_object(
         'ok',true,'contractVersion','universal_work_lifecycle_transition_v1',
         'idempotent',true,'eventId',v_event.id,'workItemId',v_work.id,
         'workState','cancelled','historicalReviewId',v_review.id,
         'originalResultId',null,'acceptedEvidenceId',null,
         'personalPerformanceClaimed',false);
     END IF;
     IF v_work.work_state<>'open'
        OR v_work.completed_at IS NOT NULL
        OR v_work.cancelled_at IS NOT NULL
     THEN RAISE EXCEPTION 'Only an original open historical Work may be retired'
       USING ERRCODE='23514'; END IF;
     -- Use the *installed* retirement dependency snapshot AND the existing
     -- cancellation guard. No bypass for requirements/relations/offers,
     -- worker projections, any prior Result or active time contracts.
     v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
     IF v_impact IS NULL
       OR v_impact->>'workState' IS DISTINCT FROM 'open'
       OR jsonb_array_length(v_impact->'requirements')<>0
       OR jsonb_array_length(v_impact->'relations')<>0
       OR jsonb_array_length(v_impact->'pendingOfferIds')<>0
       OR jsonb_array_length(v_impact->'projectionIds')<>0
       OR jsonb_array_length(v_impact->'executionResultIds')<>0
       OR jsonb_array_length(v_impact->'activeTimeContractIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAdapterIds')<>0
       OR EXISTS(SELECT 1 FROM atlas.work_allocations a
         WHERE a.work_item_id=v_work.id AND a.state='active'
           AND a.id IS DISTINCT FROM v_review.allocation_id)
       OR EXISTS(SELECT 1 FROM atlas.work_execution_plans p
         WHERE p.work_item_id=v_work.id
           AND p.plan_state IN ('active','needs_replan')
           AND p.responsible_allocation_id IS DISTINCT FROM v_review.allocation_id)
     THEN RAISE EXCEPTION 'Historical Work has dependencies needing separate governor reconciliation'
       USING ERRCODE='23514'; END IF;
     v_at:=clock_timestamp();
     -- Existing referenced responsibility and plan history survives; only
     -- the explicitly reviewed active legacy allocation/its plans unwind.
     FOR v_plan IN
       SELECT * FROM atlas.work_execution_plans p
       WHERE p.work_item_id=v_work.id
         AND p.plan_state IN ('active','needs_replan')
         AND p.responsible_allocation_id=v_review.allocation_id
       FOR UPDATE
     LOOP
       UPDATE atlas.work_execution_plans
       SET plan_state='withdrawn',updated_at=v_at,
         plan_reason='Historical obligation retired after native governor review',
         metadata=coalesce(metadata,'{}'::jsonb) ||
           jsonb_build_object('historicalRetirementReviewId',v_review.id,
                              'actorPersonId',v_actor)
       WHERE id=v_plan.id;
       INSERT INTO atlas.work_execution_plan_events(
         organization_id,work_item_id,plan_id,event_kind,
         from_planned_service_date,from_exposure_service_date,
         actor_membership_id,reason,metadata)
       VALUES(v_work.organization_id,v_work.id,v_plan.id,'withdrawn',
         v_plan.planned_service_date,v_plan.exposure_service_date,NULL,
         'Historical obligation retired after native governor review',
         jsonb_build_object('historicalRetirementReviewId',v_review.id,
                            'actorPersonId',v_actor,
                            'modernPerformanceClaimed',false));
     END LOOP;
     UPDATE atlas.work_allocations
       SET state='released',released_at=coalesce(released_at,v_at),
         updated_at=v_at,
         metadata=coalesce(metadata,'{}'::jsonb) ||
           jsonb_build_object('historicalRetirementReviewId',v_review.id,
                              'actorPersonId',v_actor,
                              'newPersonAssignmentCreated',false)
     WHERE id=v_review.allocation_id AND work_item_id=v_work.id
       AND state='active' AND establishment_basis_kind='self_adoption';
     -- Recheck with the same installed dependency helper after the unwind;
     -- the existing Work cancellation trigger independently enforces this.
     v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
     IF jsonb_array_length(v_impact->'requirements')<>0
       OR jsonb_array_length(v_impact->'relations')<>0
       OR jsonb_array_length(v_impact->'pendingOfferIds')<>0
       OR jsonb_array_length(v_impact->'projectionIds')<>0
       OR jsonb_array_length(v_impact->'executionResultIds')<>0
       OR jsonb_array_length(v_impact->'activeTimeContractIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAllocationIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activePlanIds')<>0
       OR jsonb_array_length(v_impact->'automaticUnwind'->'activeAdapterIds')<>0
     THEN RAISE EXCEPTION 'Original dependencies changed during governed retirement'
       USING ERRCODE='40001'; END IF;
     SELECT coalesce(max(e.sequence_no),0)+1 INTO v_sequence
       FROM atlas.work_lifecycle_events_v1 e WHERE e.work_item_id=v_work.id;
     INSERT INTO atlas.work_lifecycle_events_v1(
       work_item_id,organization_id,household_id,sequence_no,
       event_kind,from_state,to_state,actor_user_id,actor_attribution,
       source_table,source_row_id,source_idempotency_key,provenance_kind,
       occurred_at,evidence_refs)
     VALUES(v_work.id,v_work.organization_id,NULL,v_sequence,
       'work_transition_applied','open','cancelled',v_uid,
       'verified_signed_transition',
       'atlas.historical_self_adoption_review_events_v1',
       v_review.id,v_key,'authoritative_transition',v_at,
       jsonb_build_object(
         'transitionKind','cancel','authorityMode','native_governor_historical_retirement',
         'historicalReviewId',v_review.id,'historicalPersonLinkId',v_link.id,
         'historicalAllocationId',v_review.allocation_id,
         'ledgerId',v_review.ledger_id,'reviewOutcome','obsolete_cancelled',
         'workerPerformanceClaimed',false,'newActualRecorded',false,
         'newResultAccepted',false))
     RETURNING * INTO v_event;
     UPDATE atlas.work_items
       SET work_state='cancelled',cancelled_at=v_at,
         completed_at=NULL,updated_at=v_at
     WHERE id=v_work.id AND work_state='open';
     IF NOT FOUND OR
       (SELECT work_state FROM atlas.work_items WHERE id=v_work.id)
         IS DISTINCT FROM 'cancelled'
     THEN RAISE EXCEPTION 'Original historical Work retirement projection drifted'
       USING ERRCODE='23514'; END IF;
     RETURN jsonb_build_object(
       'ok',true,'contractVersion','universal_work_lifecycle_transition_v1',
       'idempotent',false,'eventId',v_event.id,'workItemId',v_work.id,
       'workState','cancelled','historicalReviewId',v_review.id,
       'originalResultId',null,'acceptedEvidenceId',null,
       'personalPerformanceClaimed',false);
   END;
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

-- HELD: source-only signed bridge to the single private lifecycle authority.
-- Exact historical review and current native Ledger governor only.
-- The immutable shadow base (04) predates historical review. Preserve its
-- existing allowed evidence sources and admit exactly this additional source.
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_source_table_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_source_table_check
 CHECK(source_table IN (
   'atlas.work_items','atlas.work_execution_results',
   'atlas.work_result_acceptances','atlas.work_allocations',
   'atlas.work_execution_plan_events',
   'atlas.historical_self_adoption_review_events_v1'
 ));
CREATE OR REPLACE FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_review_id uuid,
 p_impact_token text,p_action_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $retire$
DECLARE
 v_actor uuid;
 v_review atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_impact jsonb;
 v_receipt jsonb;
BEGIN
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF v_actor IS NULL OR p_review_id IS NULL OR p_action_id IS NULL
 OR p_impact_token IS NULL OR length(p_impact_token)<>32
 THEN RAISE EXCEPTION 'Exact native governor, review, token and action required'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_review FROM atlas.historical_self_adoption_review_events_v1 h
 WHERE h.id=p_review_id AND h.organization_id=p_organization_id
 AND h.ledger_id=p_ledger_id AND h.event_kind='governor_reviewed'
 AND h.outcome='obsolete_cancelled';
 IF v_review.id IS NULL THEN RAISE EXCEPTION 'Exact obsolete historical review required'
 USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.work_lifecycle_events_v1:'||v_review.work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=v_review.work_item_id AND w.organization_id=p_organization_id
 FOR UPDATE;
 IF v_work.id IS NULL THEN RAISE EXCEPTION 'Original Work unavailable'
 USING ERRCODE='42501'; END IF;
 -- Replay is validated against original reviewed source and signed actor
 -- by the private core, even after state changes.
 IF v_work.work_state='cancelled' THEN
   RETURN atlas.apply_work_lifecycle_transition_internal_v1(
     v_work.id,'cancel',v_review.id,
     'native-historical-retirement:'||p_action_id::text);
 END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
 IF md5(v_impact::text) IS DISTINCT FROM p_impact_token THEN
   RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
   USING ERRCODE='40001'; END IF;
 v_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'cancel',v_review.id,
   'native-historical-retirement:'||p_action_id::text);
 IF v_receipt->>'workState' IS DISTINCT FROM 'cancelled'
 OR v_receipt->>'historicalReviewId' IS DISTINCT FROM v_review.id::text
 THEN RAISE EXCEPTION 'Single transition retirement not confirmed'
 USING ERRCODE='23514'; END IF;
 RETURN v_receipt;
END; $retire$;
REVOKE ALL ON FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) TO authenticated;

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


COMMIT;
