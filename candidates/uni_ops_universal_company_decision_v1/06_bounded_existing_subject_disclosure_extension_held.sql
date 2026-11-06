-- UNI-OPS-01 / HELD bounded source disclosure extension, SAME native
-- append-only Subject disclosure table and signed Company governing root.
-- Source-only candidate. NOT a migration, not a generic disclosure grant.
-- Preserve every current existing supported domain and its native writer.
-- Does NOT grant ANYONE visibility merely by changing a CHECK constraint.
-- Allows only exact farm_operations Harvest batch or Seed lot identity/
-- condition decisions AFTER separately source-qualified owner action.

DO $pin_original_subject_scope$
DECLARE v_hash text;
BEGIN
 SELECT pg_catalog.md5(pg_catalog.pg_get_constraintdef(c.oid))
 INTO v_hash
 FROM pg_catalog.pg_constraint c
 JOIN pg_catalog.pg_class r ON r.oid=c.conrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
 WHERE n.nspname='atlas'
  AND r.relname='subject_disclosure_decision_events_v1'
  AND c.conname='subject_disclosure_supported_subject_v1';
 IF v_hash IS DISTINCT FROM 'd485d918b633c4ba51ea013f99e12e53'
 THEN RAISE EXCEPTION
   'Existing original Subject disclosure constraint changed; do not rewrite source law'
   USING ERRCODE='55000'; END IF;
 IF pg_catalog.to_regclass(
    'atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NOT NULL
 THEN RAISE EXCEPTION
   'Farm parallel governor writer must not precede universal source adapter'
   USING ERRCODE='55000'; END IF;
END;
$pin_original_subject_scope$;

ALTER TABLE atlas.subject_disclosure_decision_events_v1
 DROP CONSTRAINT subject_disclosure_supported_subject_v1;
ALTER TABLE atlas.subject_disclosure_decision_events_v1
 ADD CONSTRAINT subject_disclosure_supported_subject_v1
 CHECK (
    (subject_domain='spatial' AND subject_kind='growing_object'
      AND disclosure_class IN ('identity','condition'))
    OR (subject_domain='event' AND subject_kind='occurrence'
      AND disclosure_class='identity')
    OR (subject_domain='spatial' AND subject_kind='farm'
      AND disclosure_class='current_inventory')
    OR (subject_domain='farm_operations'
      AND subject_kind IN ('flower_harvest_batch','seed_lot')
      AND disclosure_class IN ('identity','condition'))
 );

-- Source-specific signed governor, not a generic "grant any source kind"
-- endpoint. The old general governor_set_subject_disclosure writer is
-- unchanged and still supports only its original Subjects.
CREATE FUNCTION atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 p_attention_id uuid,
 p_ledger_id uuid,
 p_target_person_id uuid,
 p_disclosure_class text,
 p_decision_kind text,
 p_source_action_id uuid,
 p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $disclose$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_uid uuid:=auth.uid();
 v_j atlas.journal_event_index%ROWTYPE;
 v_f atlas.farms%ROWTYPE;
 v_current atlas.subject_disclosure_decision_events_v1%ROWTYPE;
 v_event atlas.subject_disclosure_decision_events_v1%ROWTYPE;
 v_seed atlas.seed_inventory_events%ROWTYPE;
 v_pos atlas.seed_inventory_position_v1%ROWTYPE;
 v_harvest atlas.flower_harvest_bucket_observations%ROWTYPE;
 v_native_event uuid;
 v_uncovered numeric;
 v_reason text:=NULLIF(pg_catalog.btrim(p_reason),'');
BEGIN
 IF v_uid IS NULL OR v_person IS NULL OR p_attention_id IS NULL
    OR p_ledger_id IS NULL OR p_target_person_id IS NULL
    OR p_source_action_id IS NULL
    OR p_disclosure_class NOT IN ('identity','condition')
    OR p_decision_kind NOT IN ('grant','withhold')
    OR v_reason IS NULL OR pg_catalog.char_length(v_reason)
      NOT BETWEEN 12 AND 1600
 THEN RAISE EXCEPTION 'Exact signed current source disclosure decision required'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_j FROM atlas.journal_event_index j
 WHERE j.id=p_attention_id FOR UPDATE;
 SELECT * INTO v_f FROM atlas.farms f
 WHERE f.id=v_j.farm_id AND f.status='active';
 IF v_j.id IS NULL OR v_f.id IS NULL
    OR v_j.organization_id IS DISTINCT FROM v_f.organization_id
    OR v_j.visibility_scope IS DISTINCT FROM 'owner'
    OR v_j.event_kind IS DISTINCT FROM 'owner_decision'
    OR v_j.importance IS DISTINCT FROM 'attention'
    OR v_j.task_id IS NOT NULL
    OR v_j.payload->>'operationalOwnerReviewOnly' IS DISTINCT FROM 'true'
    OR v_j.payload->>'principalEscalationQualified' IS DISTINCT FROM 'false'
    OR v_j.source_kind NOT IN ('flower_harvest_batch','seed_lot')
 THEN RAISE EXCEPTION 'Exact native operational source required for disclosure'
   USING ERRCODE='42501'; END IF;

 IF atlas.company_work_native_ledger_owner_self_v1(
      v_f.organization_id,p_ledger_id) IS DISTINCT FROM v_person
   OR NOT EXISTS(
      SELECT 1 FROM atlas.farm_crop_ledger_custody_v1 c
      JOIN atlas.ledger_organization_participations lop
        ON lop.ledger_id=c.ledger_id
       AND lop.organization_id=v_f.organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind='governing'
       AND lop.is_compatibility_primary=true
      WHERE c.farm_id=v_f.id AND c.ledger_id=p_ledger_id
       AND c.custody_state='active' AND c.ended_at IS NULL)
   OR NOT atlas.person_has_native_ledger_connection_v1(
      v_f.organization_id,p_ledger_id,p_target_person_id)
 THEN RAISE EXCEPTION
   'Current native root, correct Farm custody and connected target Person required'
   USING ERRCODE='42501'; END IF;

 IF v_j.source_kind='flower_harvest_batch' THEN
   IF v_j.event_key IS DISTINCT FROM
      'harvest-preparation-needs-owner-direction:'||v_j.source_id::text
      OR v_j.source_event IS DISTINCT FROM 'harvest_output_recorded'
      OR v_j.payload->>'contractVersion' IS DISTINCT FROM
         'harvest_output_owner_attention_6a_v1'
      OR v_j.provenance->>'sourceTable' IS DISTINCT FROM
         'atlas.flower_harvest_bucket_observations'
      OR COALESCE(v_j.provenance->>'sourceObservationId','') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION 'No verified current Harvest Subject source'
       USING ERRCODE='42501'; END IF;
   v_native_event:=(v_j.provenance->>'sourceObservationId')::uuid;
   SELECT * INTO v_harvest
   FROM atlas.flower_harvest_bucket_observations o
   WHERE o.id=v_native_event AND o.batch_id=v_j.source_id
     AND o.farm_id=v_f.id;
   IF v_harvest.id IS NULL
     OR v_harvest.created_at IS DISTINCT FROM v_j.occurred_at
     OR NOT EXISTS(
       SELECT 1 FROM atlas.flower_harvest_batches b
       WHERE b.id=v_j.source_id AND b.farm_id=v_f.id)
     OR EXISTS(
       SELECT 1 FROM atlas.flower_preparation_directives d
       WHERE d.harvest_batch_id=v_j.source_id AND d.farm_id=v_f.id)
   THEN RAISE EXCEPTION 'Harvest already directed or native source unavailable'
     USING ERRCODE='42501'; END IF;
 ELSE
   IF v_j.event_key IS DISTINCT FROM
      'seed-shortfall-needs-owner-decision:'||v_j.source_id::text
      OR v_j.source_event IS DISTINCT FROM 'verified_shortfall'
      OR v_j.payload->>'contractVersion' IS DISTINCT FROM
         'seed_shortfall_owner_attention_6a_v1'
      OR v_j.provenance->>'sourceTable' IS DISTINCT FROM
         'atlas.seed_inventory_events'
      OR COALESCE(v_j.provenance->>'sourceEventId','') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION 'No native seed source for disclosure'
     USING ERRCODE='42501'; END IF;
   v_native_event:=(v_j.provenance->>'sourceEventId')::uuid;
   SELECT * INTO v_seed FROM atlas.seed_inventory_events e
   WHERE e.id=v_native_event AND e.seed_lot_id=v_j.source_id
     AND e.farm_id=v_f.id AND e.organization_id=v_f.organization_id;
   SELECT * INTO v_pos FROM atlas.seed_inventory_position_v1 p
   WHERE p.seed_lot_id=v_j.source_id AND p.farm_id=v_f.id
     AND p.count_trusted=true;
   SELECT GREATEST(COALESCE(SUM(c.outstanding_quantity),0)
       -COALESCE(v_pos.projected_on_hand_quantity,0),0)
     INTO v_uncovered
   FROM atlas.seed_allocation_coverage_v1 c
   WHERE c.seed_lot_id=v_j.source_id;
   IF v_seed.id IS NULL OR v_pos.seed_lot_id IS NULL
      OR v_pos.source_event_id IS DISTINCT FROM v_seed.id
      OR v_seed.observed_at IS DISTINCT FROM v_j.occurred_at
      OR v_uncovered<=0
      OR NOT EXISTS(
        SELECT 1 FROM atlas.seed_lots l
        WHERE l.id=v_j.source_id AND l.farm_id=v_f.id
          AND l.status NOT IN ('retired','closed'))
   THEN RAISE EXCEPTION 'No trusted current uncovered seed Subject'
     USING ERRCODE='42501'; END IF;
 END IF;

 -- Preserve original append-only source history; same exact target,
 -- source Subject and information class lock as the existing writer.
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(
    'atlas.subject_disclosure:'||p_ledger_id::text||':'||
    p_target_person_id::text||':farm_operations:'||
    v_j.source_kind||':'||v_j.source_id::text||':'||
    p_disclosure_class,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(
    'atlas.subject_action:'||p_ledger_id::text||':'||
    p_source_action_id::text,0));
 SELECT * INTO v_current
 FROM atlas.subject_disclosure_decision_events_v1 e
 WHERE e.ledger_id=p_ledger_id AND e.source_action_id=p_source_action_id;
 IF v_current.id IS NOT NULL THEN
   IF v_current.organization_id IS DISTINCT FROM v_f.organization_id
     OR v_current.target_person_id IS DISTINCT FROM p_target_person_id
     OR v_current.subject_domain IS DISTINCT FROM 'farm_operations'
     OR v_current.subject_kind IS DISTINCT FROM v_j.source_kind
     OR v_current.subject_id IS DISTINCT FROM v_j.source_id
     OR v_current.disclosure_class IS DISTINCT FROM p_disclosure_class
     OR v_current.decision_kind IS DISTINCT FROM p_decision_kind
     OR v_current.reason IS DISTINCT FROM v_reason
   THEN RAISE EXCEPTION 'Original Subject-disclosure action replay differs'
     USING ERRCODE='23505'; END IF;
   v_event:=v_current;
 ELSE
   INSERT INTO atlas.subject_disclosure_decision_events_v1(
      organization_id,ledger_id,target_person_id,subject_domain,
      subject_kind,subject_id,disclosure_class,decision_kind,
      source_action_id,reason,decided_by_person_id,recorded_at)
   VALUES(
      v_f.organization_id,p_ledger_id,p_target_person_id,
      'farm_operations',v_j.source_kind,v_j.source_id,
      p_disclosure_class,p_decision_kind,p_source_action_id,
      v_reason,v_person,pg_catalog.clock_timestamp())
   RETURNING * INTO v_event;
 END IF;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,
  'contractVersion','farm_operational_subject_disclosure_held_v1',
  'decisionId',v_event.id,
  'subjectKind',v_j.source_kind,
  'disclosureClass',p_disclosure_class,
  'decisionKind',p_decision_kind,
  'currentlyGranted',
    atlas.has_current_subject_disclosure_v1(
      p_ledger_id,p_target_person_id,'farm_operations',v_j.source_kind,
      v_j.source_id,p_disclosure_class),
  'priorSubjectDisclosureHistoryPreserved',true,
  'principalEscalationGranted',false,
  'newWorkAuthorized',false,'recipientAssigned',false);
END;
$disclose$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 uuid,uuid,uuid,text,text,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
