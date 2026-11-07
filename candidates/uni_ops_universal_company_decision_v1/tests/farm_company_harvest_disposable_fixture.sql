-- HELD UNI-OPS source-only fictional Farm/Harvest fixture.
-- DO NOT RUN IN PRODUCTION OR A RETAINED PRIVATE CLONE.
-- Depends on the original exact C1 source fixture, verified source-pinned
-- P3 14/15 + Company 01/02/03/06/04/05 full schema, and disposable PG17.
-- This seeds only a synthetic physical Harvest observation. It does NOT
-- fabricate an owner grant, farm-crop Ledger custody, source case, governor
-- decision, Worker acceptance, next Work, or Principal Clock candidate.
-- The existing P3 14 TRIGGER must construct the native Journal attention.
\set ON_ERROR_STOP on

DO $fixture_guard$
BEGIN
 IF current_database() IS DISTINCT FROM 'postgres'
 OR current_setting('uni_ops.disposable_clone',true) IS DISTINCT FROM 'true'
 OR (SELECT count(*) FROM auth.users WHERE id IN (
    'e5200000-0000-4000-8000-000000000001'::uuid,
    'e5200000-0000-4000-8000-000000000002'::uuid,
    'e5200000-0000-4000-8000-000000000003'::uuid,
    'e5200000-0000-4000-8000-000000000004'::uuid))<>4
 OR NOT EXISTS(SELECT 1 FROM atlas.farms
    WHERE id='e5200000-0000-4000-8000-000000000b01'::uuid
      AND organization_id='e5200000-0000-4000-8000-000000000801'::uuid)
 OR NOT EXISTS(SELECT 1 FROM atlas.farm_memberships
    WHERE id='e5200000-0000-4000-8000-000000000b06'::uuid
      AND user_id='e5200000-0000-4000-8000-000000000002'::uuid
      AND farm_id='e5200000-0000-4000-8000-000000000b01'::uuid
      AND active)
 OR NOT EXISTS(SELECT 1 FROM atlas.growing_objects
    WHERE id='e5200000-0000-4000-8000-000000000b03'::uuid
      AND farm_id='e5200000-0000-4000-8000-000000000b01'::uuid)
 OR EXISTS(SELECT 1 FROM atlas.farm_crop_ledger_custody_v1 WHERE
      farm_id='e5200000-0000-4000-8000-000000000b01'::uuid)
 OR EXISTS(SELECT 1 FROM atlas.uni_ops_governed_source_cases_v1)
 OR EXISTS(SELECT 1 FROM atlas.uni_ops_governed_case_decision_events_v1)
 OR pg_catalog.to_regclass(
      'atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NOT NULL
 OR EXISTS(SELECT 1 FROM atlas.flower_harvest_batches WHERE
      id='fa510000-0000-4000-8000-000000000003'::uuid)
 OR EXISTS(SELECT 1 FROM atlas.journal_event_index WHERE
      event_key='harvest-preparation-needs-owner-direction:fa510000-0000-4000-8000-000000000003')
 THEN RAISE EXCEPTION 'Refuse: fixture source/clone preconditions do not match'
   USING ERRCODE='42501';
 END IF;
END;
$fixture_guard$;

-- An original nonweekly Farm task is a SOURCE pointer for the physical
-- observation. It is NOT an authorized new Company Work or assignment.
INSERT INTO atlas.tasks(
 id,organization_id,farm_id,title,task_type,task_scope,
 task_series_key,created_by_user_id,metadata
) VALUES (
 'fa510000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'Fictional historical harvest source, not a new Company original',
 'harvest','farm_operation',NULL,
 'e5200000-0000-4000-8000-000000000002',
 '{"cloneFixture":true,"notCompanyWork":true}'::jsonb
);

INSERT INTO atlas.crop_cycles(
 id,farm_id,object_id,crop_cycle_key,crop_label,lifecycle_status,metadata
) VALUES (
 'fa510000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000b03',
 'held-uni-ops-fictional-harvest-cycle',
 'Synthetic witness flowers','active',
 '{"cloneFixture":true}'::jsonb
);

INSERT INTO atlas.flower_harvest_batches(
 id,farm_id,recorded_by_membership_id,batch_key,created_by_user_id,metadata
) VALUES (
 'fa510000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000b06',
 'held-uni-ops-nonweekly-batch',
 'e5200000-0000-4000-8000-000000000002',
 '{"cloneFixture":true}'::jsonb
);

-- The original triggered event is source evidence, not a Company governing
-- permission. The actual fictional operator is NOT claimed to have signed a
-- physical Result here; source provenance is fixture generated only.
INSERT INTO atlas.flower_harvest_bucket_observations(
 id,farm_id,batch_id,crop_cycle_id,task_id,
 recorded_by_membership_id,observed_date,bucket_band,
 bucket_equivalent_floor,idempotency_key,created_by_user_id,metadata
) VALUES (
 'fa510000-0000-4000-8000-000000000004',
 'e5200000-0000-4000-8000-000000000b01',
 'fa510000-0000-4000-8000-000000000003',
 'fa510000-0000-4000-8000-000000000002',
 'fa510000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000b06',
 (now() AT TIME ZONE 'America/Chicago')::date,'half',0.50,
 'held-uni-ops-fictional-harvest-observation',
 'e5200000-0000-4000-8000-000000000002',
 '{"cloneFixture":true,"signedActualNotClaimed":true}'::jsonb
);

DO $verify_native_source$
DECLARE v_j atlas.journal_event_index%ROWTYPE;
BEGIN
 SELECT * INTO v_j FROM atlas.journal_event_index
 WHERE event_key='harvest-preparation-needs-owner-direction:fa510000-0000-4000-8000-000000000003';
 IF v_j.id IS NULL
    OR v_j.source_kind IS DISTINCT FROM 'flower_harvest_batch'
    OR v_j.source_id IS DISTINCT FROM
      'fa510000-0000-4000-8000-000000000003'::uuid
    OR v_j.source_event IS DISTINCT FROM 'harvest_output_recorded'
    OR v_j.event_kind IS DISTINCT FROM 'owner_decision'
    OR v_j.visibility_scope IS DISTINCT FROM 'owner'
    OR v_j.task_id IS NOT NULL
    OR v_j.payload->>'operationalOwnerReviewOnly' IS DISTINCT FROM 'true'
    OR v_j.payload->>'principalEscalationQualified' IS DISTINCT FROM 'false'
    OR v_j.payload->>'principalClockCandidateCreated' IS DISTINCT FROM 'false'
    OR v_j.provenance->>'sourceObservationId' IS DISTINCT FROM
      'fa510000-0000-4000-8000-000000000004'
    OR EXISTS(SELECT 1 FROM atlas.flower_preparation_directives
       WHERE harvest_batch_id='fa510000-0000-4000-8000-000000000003'::uuid)
    OR EXISTS(SELECT 1 FROM atlas.uni_ops_governed_source_cases_v1)
    OR EXISTS(SELECT 1 FROM atlas.uni_ops_governed_case_decision_events_v1)
 THEN RAISE EXCEPTION 'Synthetic Harvest did not produce authentic P3 source without Work'
   USING ERRCODE='23514'; END IF;
 RAISE NOTICE 'PASS first-party P3 Harvest trigger generated owner-only attention; zero Company decisions';
END;
$verify_native_source$;
