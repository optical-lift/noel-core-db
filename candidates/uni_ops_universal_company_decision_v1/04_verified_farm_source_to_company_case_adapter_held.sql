-- UNI-OPS-01 / first REAL source adapter for the universal Company
-- case kernel. HELD, NOT A MIGRATION OR LIVE ACCESS GRANT.
-- Domain-specific ONLY: nonweekly Flower Harvest bucket observation and
-- currently trusted uncovered Seed inventory against real commitments.
-- Neither is a Principal Clock candidate or automatic Work permission.
-- Existing farm P3 17 independent decision table must NOT be installed.
-- Requires the source-only held P3 14/15 observation-to-Journal overlays
-- and U1B's real native Farm -> Company governing Ledger custody.
-- Weekly Harvest P3 10 and other sources are intentionally NOT admitted.

CREATE TABLE atlas.uni_ops_farm_company_source_links_v1 (
 case_id uuid PRIMARY KEY
   REFERENCES atlas.uni_ops_governed_source_cases_v1(id)
   ON DELETE RESTRICT,
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id)
   ON DELETE RESTRICT,
 governing_ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id)
   ON DELETE RESTRICT,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id)
   ON DELETE RESTRICT,
 attention_journal_event_id uuid NOT NULL
   REFERENCES atlas.journal_event_index(id) ON DELETE RESTRICT,
 farm_source_kind text NOT NULL
   CHECK (farm_source_kind IN ('flower_harvest_batch','seed_lot')),
 native_subject_id uuid NOT NULL,
 native_evidence_event_id uuid NOT NULL,
 source_attestation_fingerprint text NOT NULL
   CHECK(source_attestation_fingerprint ~ '^[0-9a-f]{32}$'),
 source_evidence_recorded_at timestamptz NOT NULL,
 source_link_recorded_at timestamptz NOT NULL
   DEFAULT pg_catalog.clock_timestamp(),
 CONSTRAINT uni_ops_farm_company_source_case_scope_v1
   FOREIGN KEY(case_id,organization_id,governing_ledger_id)
   REFERENCES atlas.uni_ops_governed_source_cases_v1(
      id,organization_id,governing_ledger_id)
   ON DELETE RESTRICT
);
CREATE INDEX uni_ops_farm_company_source_lookup_v1
 ON atlas.uni_ops_farm_company_source_links_v1(
  farm_id,attention_journal_event_id,source_link_recorded_at DESC);
ALTER TABLE atlas.uni_ops_farm_company_source_links_v1
 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.uni_ops_farm_company_source_links_v1
 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.uni_ops_farm_company_source_links_v1
 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER uni_ops_farm_company_source_link_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.uni_ops_farm_company_source_links_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.uni_ops_governed_no_history_rewrite_v1();

-- Real source/verifier. This is not a generic verified=true API.
-- All source claims MUST be determined from native provider records and
-- current per-information-type disclosure, never from a client-supplied
-- source key, guessed Subject, title, JSON flag or journal alone.
CREATE FUNCTION atlas.uni_ops_farm_current_attention_attestation_self_held_v1(
 p_attention_id uuid,
 p_ledger_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $attest$
DECLARE
 v_uid uuid:=auth.uid();
 v_person uuid:=atlas.current_person_id_v1();
 v_j atlas.journal_event_index%ROWTYPE;
 v_f atlas.farms%ROWTYPE;
 v_ob atlas.flower_harvest_bucket_observations%ROWTYPE;
 v_batch atlas.flower_harvest_batches%ROWTYPE;
 v_seed atlas.seed_inventory_events%ROWTYPE;
 v_lot atlas.seed_lots%ROWTYPE;
 v_pos atlas.seed_inventory_position_v1%ROWTYPE;
 v_native_event uuid;
 v_shortfall numeric;
 v_evidence_at timestamptz;
 v_scope text;
 v_snapshot jsonb;
 v_hash text;
 v_source_key text;
 v_source_revision text;
 v_contract text;
BEGIN
 IF v_uid IS NULL OR v_person IS NULL OR p_attention_id IS NULL
    OR p_ledger_id IS NULL THEN
  RAISE EXCEPTION 'Exact signed source and Ledger required'
   USING ERRCODE='42501';
 END IF;
 -- FOR SHARE is compatible with outer FOR UPDATE lock in register/decide
 -- wrappers and prevents a same-row source journal update from racing
 -- a verified case insertion or signed governor decision.
 SELECT * INTO v_j FROM atlas.journal_event_index j
 WHERE j.id=p_attention_id FOR SHARE;
 SELECT * INTO v_f FROM atlas.farms f
 WHERE f.id=v_j.farm_id AND f.status='active';
 IF v_j.id IS NULL OR v_f.id IS NULL
    OR v_j.organization_id IS DISTINCT FROM v_f.organization_id
    OR v_j.event_kind IS DISTINCT FROM 'owner_decision'
    OR v_j.visibility_scope IS DISTINCT FROM 'owner'
    OR v_j.importance IS DISTINCT FROM 'attention'
    OR v_j.task_id IS NOT NULL
    OR v_j.payload->>'operationalOwnerReviewOnly' IS DISTINCT FROM 'true'
    OR v_j.payload->>'principalEscalationQualified' IS DISTINCT FROM 'false'
    OR v_j.payload->>'principalClockCandidateCreated' IS DISTINCT FROM 'false'
    OR v_j.source_kind NOT IN ('flower_harvest_batch','seed_lot')
 THEN RAISE EXCEPTION 'Authentic operational owner source attention required'
   USING ERRCODE='42501'; END IF;

 -- Real Farm custody is an adapter requirement; universal kernel itself
 -- must remain independent of Farm, region, crop or chosen organization.
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
 THEN RAISE EXCEPTION
  'Actual signed governing Company Ledger and native Farm custody required'
  USING ERRCODE='42501'; END IF;

 IF v_j.source_kind='flower_harvest_batch' THEN
   v_contract:='farm_harvest_observation_owner_attention_v1';
   IF v_j.source_event IS DISTINCT FROM 'harvest_output_recorded'
     OR v_j.event_key IS DISTINCT FROM
        'harvest-preparation-needs-owner-direction:'||v_j.source_id::text
     OR v_j.payload->>'contractVersion' IS DISTINCT FROM
        'harvest_output_owner_attention_6a_v1'
     OR v_j.provenance->>'sourceTable' IS DISTINCT FROM
        'atlas.flower_harvest_bucket_observations'
     OR COALESCE(v_j.provenance->>'sourceObservationId','') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION 'Real nonweekly Harvest source provenance required'
      USING ERRCODE='42501'; END IF;
   v_native_event:=(v_j.provenance->>'sourceObservationId')::uuid;
   SELECT * INTO v_ob
   FROM atlas.flower_harvest_bucket_observations o
   WHERE o.id=v_native_event
     AND o.farm_id=v_f.id AND o.batch_id=v_j.source_id;
   SELECT * INTO v_batch
   FROM atlas.flower_harvest_batches b
   WHERE b.id=v_j.source_id AND b.farm_id=v_f.id;
   IF v_ob.id IS NULL OR v_batch.id IS NULL
     OR v_ob.created_at IS DISTINCT FROM v_j.occurred_at
     OR v_j.payload->>'sourceBucketObservationId'
        IS DISTINCT FROM v_ob.id::text
     OR v_j.payload->>'harvestBatchId'
        IS DISTINCT FROM v_batch.id::text
     OR NOT EXISTS(
       SELECT 1 FROM atlas.tasks t
       WHERE t.id=v_ob.task_id AND t.farm_id=v_f.id
         AND t.task_series_key IS DISTINCT FROM
             'anna_harvest_thursday_weekly')
     OR NOT EXISTS(
       SELECT 1 FROM atlas.farm_memberships m
       WHERE m.id=v_ob.recorded_by_membership_id
         AND m.farm_id=v_f.id)
     OR EXISTS(
       SELECT 1 FROM atlas.flower_preparation_directives d
       WHERE d.farm_id=v_f.id AND d.harvest_batch_id=v_batch.id)
   THEN RAISE EXCEPTION
     'Current real undirected harvested batch evidence unavailable'
     USING ERRCODE='42501'; END IF;
   v_evidence_at:=v_ob.created_at;
   v_scope:='flower_harvest_batch';
   v_snapshot:=pg_catalog.jsonb_build_object(
     'farmId',v_f.id,'batchId',v_batch.id,
     'observationId',v_ob.id,'observationRecordedAt',v_ob.created_at,
     'sourceBucketBand',v_ob.bucket_band,
     'sourceBucketFloor',v_ob.bucket_equivalent_floor,
     'sourceTaskId',v_ob.task_id);
 ELSE
   v_contract:='farm_verified_seed_coverage_attention_v1';
   IF v_j.source_event IS DISTINCT FROM 'verified_shortfall'
     OR v_j.event_key IS DISTINCT FROM
        'seed-shortfall-needs-owner-decision:'||v_j.source_id::text
     OR v_j.payload->>'contractVersion' IS DISTINCT FROM
        'seed_shortfall_owner_attention_6a_v1'
     OR v_j.provenance->>'sourceTable' IS DISTINCT FROM
        'atlas.seed_inventory_events'
     OR COALESCE(v_j.provenance->>'sourceEventId','') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   THEN RAISE EXCEPTION
      'Real verified physical seed inventory event provenance required'
      USING ERRCODE='42501'; END IF;
   v_native_event:=(v_j.provenance->>'sourceEventId')::uuid;
   SELECT * INTO v_seed
   FROM atlas.seed_inventory_events e
   WHERE e.id=v_native_event
     AND e.farm_id=v_f.id
     AND e.organization_id=v_f.organization_id
     AND e.seed_lot_id=v_j.source_id;
   SELECT * INTO v_lot FROM atlas.seed_lots l
   WHERE l.id=v_j.source_id AND l.farm_id=v_f.id
     AND l.status NOT IN ('retired','closed');
   SELECT * INTO v_pos FROM atlas.seed_inventory_position_v1 p
   WHERE p.seed_lot_id=v_j.source_id AND p.farm_id=v_f.id
     AND p.count_trusted=true;
   IF v_seed.id IS NULL OR v_lot.id IS NULL OR v_pos.seed_lot_id IS NULL
      OR v_pos.source_event_id IS DISTINCT FROM v_seed.id
      OR v_seed.observed_at IS DISTINCT FROM v_j.occurred_at
      OR v_j.payload->>'seedInventoryEventId' IS DISTINCT FROM
         v_seed.id::text
      OR v_seed.outcome NOT IN (
        'count_confirmed','count_corrected','restocked','depleted',
        'lower_bound_confirmed','direct_sow_exact_remaining')
   THEN RAISE EXCEPTION
      'Seed source event not the latest trusted current position'
      USING ERRCODE='42501'; END IF;
   SELECT pg_catalog.greatest(
       pg_catalog.coalesce(pg_catalog.sum(c.outstanding_quantity),0)
       -pg_catalog.coalesce(v_pos.projected_on_hand_quantity,0),0)
     INTO v_shortfall
   FROM atlas.seed_allocation_coverage_v1 c
   WHERE c.seed_lot_id=v_lot.id;
   IF v_shortfall IS NULL OR v_shortfall<=0 THEN
     RAISE EXCEPTION 'No current trusted uncovered seed commitment'
       USING ERRCODE='42501'; END IF;
   v_evidence_at:=v_seed.observed_at;
   v_scope:='seed_lot';
   v_snapshot:=pg_catalog.jsonb_build_object(
     'farmId',v_f.id,'seedLotId',v_lot.id,
     'inventoryEventId',v_seed.id,
     'inventoryObservedAt',v_seed.observed_at,
     'sourceOutcome',v_seed.outcome,
     'countTrusted',v_pos.count_trusted,
     'projectedOnHand',v_pos.projected_on_hand_quantity,
     'currentOutstandingUncovered',v_shortfall,
     'inventoryUnit',v_lot.quantity_unit);
 END IF;

 -- Source-native Subject disclosure is not a root-role blanket exception.
 -- IMPORTANT: these source-specific identity/condition grants do not yet
 -- exist for all farm users. Missing genuine source decisions cause HOLD,
 -- rather than silently granting universal visibility to a Farm owner.
 IF NOT COALESCE(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_person,'farm_operations',v_scope,v_j.source_id,
    'identity'),false)
 OR NOT COALESCE(atlas.has_current_subject_disclosure_v1(
    p_ledger_id,v_person,'farm_operations',v_scope,v_j.source_id,
    'condition'),false)
 THEN RAISE EXCEPTION
  'Current independent native Subject identity and condition disclosure required'
   USING ERRCODE='42501'; END IF;

 v_hash:=pg_catalog.md5(v_snapshot::text);
 v_source_key:=v_f.id::text||':'||v_j.source_id::text;
 v_source_revision:=v_native_event::text||':'||v_hash;
 RETURN pg_catalog.jsonb_build_object(
  'ok',true,
  'contractVersion','farm_to_universal_source_attestation_held_v1',
  'organizationId',v_f.organization_id,
  'governingLedgerId',p_ledger_id,
  'farmId',v_f.id,
  'attentionJournalEventId',v_j.id,
  'sourceDomain','farm_operations',
  'sourceKind',v_scope,
  'sourceSubjectId',v_j.source_id,
  'sourceEvidenceEventId',v_native_event,
  'sourceEvidenceRecordedAt',v_evidence_at,
  'sourceKey',v_source_key,
  'sourceRevisionKey',v_source_revision,
  'sourceAttestationFingerprint',v_hash,
  'sourceAdapterContract',v_contract,
  'operationalGovernorReviewOnly',true,
  'principalEscalationQualified',false,
  'principalClockCandidateCreated',false,
  'subjectDisclosuresVerifiedCurrently',true,
  'newOriginalWorkCreated',false,
  'workerAcceptanceEstablished',false);
END;
$attest$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_farm_current_attention_attestation_self_held_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Only a real CURRENT source attest may register one company case; no
-- generic "verified" admission RPC exists. The current governing Person
-- remains distinct from the source reporter and from future Work recipient.
CREATE FUNCTION atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(
 p_attention_id uuid,
 p_ledger_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $admit$
DECLARE
 v_a jsonb;
 v_j atlas.journal_event_index%ROWTYPE;
 v_case atlas.uni_ops_governed_source_cases_v1%ROWTYPE;
 v_link atlas.uni_ops_farm_company_source_links_v1%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR p_attention_id IS NULL
   OR p_ledger_id IS NULL THEN
   RAISE EXCEPTION 'Current signed source admission required'
    USING ERRCODE='42501'; END IF;

 SELECT * INTO v_j FROM atlas.journal_event_index j
 WHERE j.id=p_attention_id FOR UPDATE;
 IF v_j.id IS NULL THEN
   RAISE EXCEPTION 'Exact physical owner attention source unavailable'
     USING ERRCODE='42501'; END IF;
 v_a:=atlas.uni_ops_farm_current_attention_attestation_self_held_v1(
   p_attention_id,p_ledger_id);
 IF v_a->>'ok' IS DISTINCT FROM 'true'
    OR v_a->>'principalEscalationQualified' IS DISTINCT FROM 'false'
    OR v_a->>'subjectDisclosuresVerifiedCurrently' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'Independent source attestation failed'
   USING ERRCODE='42501'; END IF;

 INSERT INTO atlas.uni_ops_governed_source_cases_v1(
   organization_id,governing_ledger_id,source_domain,source_kind,
   source_key,source_revision_key,source_evidence_recorded_at,
   source_adapter_contract,source_attestation_fingerprint,
   source_admission_state,attention_contract)
 VALUES(
   (v_a->>'organizationId')::uuid,p_ledger_id,
   v_a->>'sourceDomain',v_a->>'sourceKind',
   v_a->>'sourceKey',v_a->>'sourceRevisionKey',
   (v_a->>'sourceEvidenceRecordedAt')::timestamptz,
   v_a->>'sourceAdapterContract',
   v_a->>'sourceAttestationFingerprint',
   'source_verified_by_adapter','operational_governor_review_v1')
 ON CONFLICT ON CONSTRAINT uni_ops_governed_case_one_revision_v1
 DO NOTHING
 RETURNING * INTO v_case;

 IF v_case.id IS NULL THEN
   SELECT * INTO v_case FROM atlas.uni_ops_governed_source_cases_v1 c
   WHERE c.organization_id=(v_a->>'organizationId')::uuid
     AND c.governing_ledger_id=p_ledger_id
     AND c.source_domain=v_a->>'sourceDomain'
     AND c.source_kind=v_a->>'sourceKind'
     AND c.source_key=v_a->>'sourceKey'
     AND c.source_revision_key=v_a->>'sourceRevisionKey';
 END IF;

 IF v_case.id IS NULL
    OR v_case.source_attestation_fingerprint IS DISTINCT FROM
       v_a->>'sourceAttestationFingerprint'
    OR v_case.source_adapter_contract IS DISTINCT FROM
       v_a->>'sourceAdapterContract'
    OR v_case.source_evidence_recorded_at IS DISTINCT FROM
       (v_a->>'sourceEvidenceRecordedAt')::timestamptz
    OR v_case.source_admission_state IS DISTINCT FROM
       'source_verified_by_adapter'
    OR v_case.attention_contract IS DISTINCT FROM
       'operational_governor_review_v1'
 THEN RAISE EXCEPTION
   'Current physical source revision conflicts with an existing case'
    USING ERRCODE='23505'; END IF;

 INSERT INTO atlas.uni_ops_farm_company_source_links_v1(
   case_id,organization_id,governing_ledger_id,farm_id,
   attention_journal_event_id,farm_source_kind,native_subject_id,
   native_evidence_event_id,source_attestation_fingerprint,
   source_evidence_recorded_at)
 VALUES(
   v_case.id,v_case.organization_id,p_ledger_id,
   (v_a->>'farmId')::uuid,p_attention_id,v_a->>'sourceKind',
   (v_a->>'sourceSubjectId')::uuid,
   (v_a->>'sourceEvidenceEventId')::uuid,
   v_a->>'sourceAttestationFingerprint',
   (v_a->>'sourceEvidenceRecordedAt')::timestamptz)
 ON CONFLICT (case_id) DO NOTHING;

 SELECT * INTO v_link FROM atlas.uni_ops_farm_company_source_links_v1
 WHERE case_id=v_case.id;
 IF v_link.case_id IS NULL
    OR v_link.attention_journal_event_id IS DISTINCT FROM p_attention_id
    OR v_link.governing_ledger_id IS DISTINCT FROM p_ledger_id
    OR v_link.farm_id IS DISTINCT FROM (v_a->>'farmId')::uuid
    OR v_link.native_subject_id IS DISTINCT FROM
       (v_a->>'sourceSubjectId')::uuid
    OR v_link.native_evidence_event_id IS DISTINCT FROM
       (v_a->>'sourceEvidenceEventId')::uuid
    OR v_link.source_attestation_fingerprint IS DISTINCT FROM
       v_a->>'sourceAttestationFingerprint'
 THEN RAISE EXCEPTION
    'Source-linked immutable Company case differs from the true physical evidence'
    USING ERRCODE='23505'; END IF;

 RETURN pg_catalog.jsonb_build_object(
  'ok',true,'contractVersion','farm_company_case_admission_held_v1',
  'sourceCaseId',v_case.id,
  'sourceEvidenceEventId',v_link.native_evidence_event_id,
  'sourceCaseRegisteredAt',v_case.source_registered_at,
  'sourceLinkRecordedAt',v_link.source_link_recorded_at,
  'operationalGovernorReviewOnly',true,
  'principalEscalationQualified',false,
  'noPrincipalClockCreated',true,
  'newWorkCreated',false,'recipientAccepted',false,
  'separateSourceQualifiedGovernorDecisionRequired',true,
  'separateRulebookAndWorkIssuerRequired',true);
END;
$admit$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
