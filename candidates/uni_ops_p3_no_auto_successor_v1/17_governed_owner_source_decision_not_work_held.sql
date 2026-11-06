-- UNI-OPS-01 / P3 / first native owner decision over SOURCE ATTENTION.
-- HELD SOURCE ONLY, NOT MIGRATED/COMPILED OR PUBLICLY EXPOSED.
-- Owner choice is not a U2 offer, Work establishment, delegated worker
-- authority, accepted Result, physical repair or scheduled successor.
-- Exact U1B farm->governing Company Ledger source is REQUIRED.
-- Existing U2A only supports native mowing Rhythm, NOT this source.
CREATE TABLE atlas.uni_ops_p3_owner_attention_decision_events_v1(
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 attention_id uuid NOT NULL
   REFERENCES atlas.journal_event_index(id) ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id)
   ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id) ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
 source_kind text NOT NULL
   CHECK(source_kind IN ('flower_harvest_batch','seed_lot')),
 source_id uuid NOT NULL,
 source_action_id uuid NOT NULL UNIQUE,
 previous_decision_id uuid REFERENCES
   atlas.uni_ops_p3_owner_attention_decision_events_v1(id)
   ON DELETE RESTRICT,
 governor_person_id uuid NOT NULL
   REFERENCES reality.entities(id) ON DELETE RESTRICT,
 governor_user_id uuid NOT NULL REFERENCES auth.users(id)
   ON DELETE RESTRICT,
 decision text NOT NULL CHECK(decision IN (
    'request_independent_work_admission',
    'hold_for_new_observation',
    'decline_new_work_at_present'
 )),
 reason text NOT NULL
   CHECK(pg_catalog.char_length(reason) BETWEEN 12 AND 1500),
 observed_trusted_shortfall numeric
   CHECK(observed_trusted_shortfall IS NULL
          OR observed_trusted_shortfall>0),
 source_evidence_event_recorded_at timestamptz NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 issued_original_work_id uuid DEFAULT NULL
   CHECK(issued_original_work_id IS NULL),
 assigned_person_id uuid DEFAULT NULL
   CHECK(assigned_person_id IS NULL),
 CHECK ((source_kind='seed_lot' AND observed_trusted_shortfall IS NOT NULL)
    OR (source_kind='flower_harvest_batch'
       AND observed_trusted_shortfall IS NULL))
);
CREATE INDEX uni_ops_p3_owner_attention_decision_chain_v1
 ON atlas.uni_ops_p3_owner_attention_decision_events_v1(
   attention_id,recorded_at DESC,id DESC);
ALTER TABLE atlas.uni_ops_p3_owner_attention_decision_events_v1
 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_p3_owner_attention_decision_events_v1
 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_p3_owner_attention_decision_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_p3_owner_attention_decision_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $immutable$
BEGIN
 RAISE EXCEPTION 'A governed owner source decision is immutable'
  USING ERRCODE='42501';
END;
$immutable$;
CREATE TRIGGER uni_ops_p3_owner_attention_decision_immutable_v1
 BEFORE UPDATE OR DELETE
 ON atlas.uni_ops_p3_owner_attention_decision_events_v1
 FOR EACH ROW EXECUTE FUNCTION
 atlas.uni_ops_p3_owner_attention_decision_immutable_v1();
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p3_owner_attention_decision_immutable_v1()
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_p3_owner_decide_source_attention_self_held_v1(
 p_attention_id uuid,
 p_ledger_id uuid,
 p_decision text,
 p_reason text,
 p_action_id uuid,
 p_expected_previous_decision_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $decision$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_attention atlas.journal_event_index%ROWTYPE;
 v_farm atlas.farms%ROWTYPE;
 v_root uuid;
 v_reason text:=nullif(pg_catalog.btrim(p_reason),'');
 v_current_shortfall numeric;
 v_current_seed_trusted boolean:=false;
 v_latest atlas.uni_ops_p3_owner_attention_decision_events_v1%ROWTYPE;
 v_prior atlas.uni_ops_p3_owner_attention_decision_events_v1%ROWTYPE;
 v_event atlas.uni_ops_p3_owner_attention_decision_events_v1%ROWTYPE;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL
    OR p_attention_id IS NULL OR p_ledger_id IS NULL
    OR p_action_id IS NULL
    OR p_decision IS NULL OR p_decision NOT IN (
      'request_independent_work_admission',
      'hold_for_new_observation',
      'decline_new_work_at_present')
    OR v_reason IS NULL OR pg_catalog.char_length(v_reason)
       NOT BETWEEN 12 AND 1500
 THEN RAISE EXCEPTION 'Exact signed current governing source decision required'
   USING ERRCODE='42501'; END IF;

 -- Lock the actual first-party attention source, serializing with another
 -- physical source update of its one stable journal event.
 SELECT * INTO v_attention
 FROM atlas.journal_event_index j
 WHERE j.id=p_attention_id FOR UPDATE;
 SELECT * INTO v_farm FROM atlas.farms f
 WHERE f.id=v_attention.farm_id AND f.status='active';
 IF v_attention.id IS NULL OR v_farm.id IS NULL
    OR v_attention.organization_id IS DISTINCT FROM v_farm.organization_id
    OR v_attention.visibility_scope IS DISTINCT FROM 'owner'
    OR v_attention.event_kind IS DISTINCT FROM 'owner_decision'
    OR v_attention.importance IS DISTINCT FROM 'attention'
    OR NOT (
      (v_attention.source_kind='flower_harvest_batch'
       AND (
          v_attention.event_key LIKE 'weekly-harvest-owner-direction-pending:%'
          OR v_attention.event_key LIKE
             'harvest-preparation-needs-owner-direction:%'))
      OR
      (v_attention.source_kind='seed_lot'
       AND v_attention.event_key LIKE 'seed-shortfall-needs-owner-decision:%')
    )
 THEN RAISE EXCEPTION 'Original owner attention unavailable'
   USING ERRCODE='42501'; END IF;

 v_root:=atlas.company_work_native_ledger_owner_self_v1(
    v_farm.organization_id,p_ledger_id);
 IF v_root IS NULL OR v_root IS DISTINCT FROM v_person
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farm_crop_ledger_custody_v1 c
      JOIN atlas.ledger_organization_participations lop
        ON lop.ledger_id=c.ledger_id
       AND lop.organization_id=v_farm.organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      WHERE c.farm_id=v_farm.id AND c.ledger_id=p_ledger_id
        AND c.custody_state='active' AND c.ended_at IS NULL
    )
 THEN RAISE EXCEPTION
   'Actual current governing native farm Ledger Person required'
   USING ERRCODE='42501'; END IF;

 -- Recheck REAL current physical source condition before considering a
 -- choice. A title, clock due date, Report or Journal alone is not Need.
 IF v_attention.source_kind='flower_harvest_batch' THEN
    IF NOT EXISTS(
      SELECT 1 FROM atlas.flower_harvest_batches b
      WHERE b.id=v_attention.source_id AND b.farm_id=v_farm.id)
    OR EXISTS(
      SELECT 1 FROM atlas.flower_preparation_directives d
      WHERE d.harvest_batch_id=v_attention.source_id
        AND d.farm_id=v_farm.id)
    THEN RAISE EXCEPTION
       'Harvest source already directed or not in this Farm'
       USING ERRCODE='42501'; END IF;
 ELSE
    SELECT coalesce(p.count_trusted,false),
       greatest(
         coalesce((SELECT sum(c.outstanding_quantity)
          FROM atlas.seed_allocation_coverage_v1 c
          WHERE c.seed_lot_id=p.seed_lot_id),0)
         -coalesce(p.projected_on_hand_quantity,0),0)
      INTO v_current_seed_trusted,v_current_shortfall
    FROM atlas.seed_inventory_position_v1 p
    JOIN atlas.seed_lots l ON l.id=p.seed_lot_id
    WHERE p.seed_lot_id=v_attention.source_id
      AND p.farm_id=v_farm.id AND l.farm_id=v_farm.id
      AND l.status<>'retired';
    IF NOT coalesce(v_current_seed_trusted,false)
       OR coalesce(v_current_shortfall,0)<=0
    THEN RAISE EXCEPTION
      'No currently trusted uncovered seed production requirement'
      USING ERRCODE='42501'; END IF;
 END IF;

 -- Every correction is a new source event, never mutation of the old
 -- governor's decision. An exact prior ID is required for continuation.
 SELECT * INTO v_latest
 FROM atlas.uni_ops_p3_owner_attention_decision_events_v1 e
 WHERE e.attention_id=v_attention.id
 ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO v_prior
 FROM atlas.uni_ops_p3_owner_attention_decision_events_v1 e
 WHERE e.source_action_id=p_action_id;
 IF v_prior.id IS NOT NULL THEN
    IF v_prior.attention_id IS DISTINCT FROM v_attention.id
       OR v_prior.ledger_id IS DISTINCT FROM p_ledger_id
       OR v_prior.governor_person_id IS DISTINCT FROM v_person
       OR v_prior.governor_user_id IS DISTINCT FROM v_uid
       OR v_prior.source_kind IS DISTINCT FROM v_attention.source_kind
       OR v_prior.source_id IS DISTINCT FROM v_attention.source_id
       OR v_prior.previous_decision_id IS DISTINCT FROM
           p_expected_previous_decision_id
       OR v_prior.decision IS DISTINCT FROM p_decision
       OR v_prior.reason IS DISTINCT FROM v_reason
    THEN RAISE EXCEPTION 'Source decision replay changed meaning'
      USING ERRCODE='23505'; END IF;
    RETURN pg_catalog.jsonb_build_object(
      'ok',true,'contractVersion','p3_owner_source_decision_v1',
      'decisionEventId',v_prior.id,'replay',true,
      'decision',v_prior.decision,
      'originalWorkCreated',false,'workerAssigned',false,
      'nativeU2AuthorizationEstablished',false);
 END IF;
 IF v_latest.id IS DISTINCT FROM p_expected_previous_decision_id
 THEN RAISE EXCEPTION
   'Current exact previous governor decision is required'
   USING ERRCODE='23505'; END IF;

 INSERT INTO atlas.uni_ops_p3_owner_attention_decision_events_v1(
    attention_id,organization_id,ledger_id,farm_id,
    source_kind,source_id,source_action_id,previous_decision_id,
    governor_person_id,governor_user_id,decision,reason,
    observed_trusted_shortfall,source_evidence_event_recorded_at)
 VALUES(
    v_attention.id,v_farm.organization_id,p_ledger_id,v_farm.id,
    v_attention.source_kind,v_attention.source_id,p_action_id,
    p_expected_previous_decision_id,v_person,v_uid,p_decision,v_reason,
    CASE WHEN v_attention.source_kind='seed_lot'
       THEN v_current_shortfall ELSE NULL END,
    v_attention.occurred_at)
 RETURNING * INTO v_event;
 RETURN pg_catalog.jsonb_build_object(
    'ok',true,'contractVersion','p3_owner_source_decision_v1',
    'decisionEventId',v_event.id,'sourceAttentionId',v_attention.id,
    'decision',v_event.decision,'replay',false,
    'decisionRecordedAt',v_event.recorded_at,
    'sourceEvidenceEventRecordedAt',
      v_event.source_evidence_event_recorded_at,
    'currentlyTrustedShortfall',v_event.observed_trusted_shortfall,
    'independentWorkSourceAdmissionRequested',
       v_event.decision='request_independent_work_admission',
    'independentWorkSourceAdmissionApproved',false,
    'noNewOriginalWorkCreated',true,
    'workerAssignmentCreated',false,
    'workerConsentInferred',false,
    'scheduledSuccessorCreated',false,
    'operationalSourceDecisionOnly',true,
    'principalEscalationQualified',false,
    'principalClockCandidateCreated',false,
    'nonRhythmOriginalIssuerStillRequired',true);
END;
$decision$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_p3_owner_decide_source_attention_self_held_v1(
 uuid,uuid,text,text,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
