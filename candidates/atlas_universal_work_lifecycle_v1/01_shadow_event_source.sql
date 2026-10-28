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
   'source_signed_user','session_claim_only','unattributed'
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
   'source_signed_user','session_claim_only','unattributed')
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
 IF p_event_kind IN ('historical_state_snapshot','result_reported',
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
