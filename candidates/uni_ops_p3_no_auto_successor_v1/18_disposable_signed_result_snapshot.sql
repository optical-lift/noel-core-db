-- UNI-OPS-01 / P3 6A isolated, read-only before/after signed Result snapshot.
-- HELD TEST SOURCE ONLY: never a migration. Run only against an independently
-- approved disposable current-schema PG17 clone after U1/U2C + P1/C1/P3
-- assembly. No fixture creation, grants, mutation, Result or impersonation.
--
-- Example in the isolated test job, using fictional UUIDs already verified
-- by the signed test fixture (not by this read-only query):
-- psql -X -qAt -v ON_ERROR_STOP=1 -v organization_id=... -v rhythm_state_id=...
--    -v work_item_id=... -v phase=before -f 18_disposable_signed_result_snapshot.sql
-- Repeat with phase=after after ONE truly signed worker Actual. Capture only
-- the one emitted JSON object; use 19_compare_signed_result_snapshots.mjs
-- externally to compare. No auth token, Person roster or private notes output.
--
-- This intentionally checks the whole organization Work/Task counts in a
-- disposable exclusive fixture, not just the correct original: an unwanted
-- different-Subject successor would otherwise be invisible.
-- If U2E campaign tables are installed, stop: this base snapshot cannot
-- claim zero campaigns without their separately authorized row census.
\set ON_ERROR_STOP on
WITH requested AS (
 SELECT :'organization_id'::uuid AS org_id,
        :'rhythm_state_id'::uuid AS rhythm_id,
        :'work_item_id'::uuid AS work_id,
        :'phase'::text AS phase
), original AS (
 SELECT w.id,w.work_state,w.source_object_type,w.source_object_id,
        w.result_contract_key,w.metadata,w.created_at
 FROM atlas.work_items w CROSS JOIN requested p
 WHERE w.id=p.work_id AND w.organization_id=p.org_id
), actual_state AS (
 SELECT s.id,s.organization_id,s.farm_id,s.state,
        s.last_qualifying_satisfaction_id,s.warning_at,s.due_at,s.failure_at
 FROM atlas.rhythm_state s CROSS JOIN requested p
 WHERE s.id=p.rhythm_id AND s.organization_id=p.org_id
)
SELECT jsonb_build_object(
 'contract','uni_ops_p3_signed_result_snapshot_v1',
 'phase',p.phase,
 'validExactOriginal',
    (SELECT count(*)=1 FROM original o WHERE
      o.source_object_type='rhythm_state' AND o.source_object_id=p.rhythm_id
      AND o.result_contract_key='continuing_care_actual_v1'
      AND o.metadata->>'sourceContract'='continuing_original_work_v1'),
 'validRhythmState',(SELECT count(*)=1 FROM actual_state),
 'originalWorkState',(SELECT o.work_state FROM original o),
 'rhythmState',(SELECT s.state FROM actual_state s),
 'qualifyingSatisfactionId',(SELECT s.last_qualifying_satisfaction_id FROM actual_state s),
 'nextEligibleAt',(SELECT s.due_at FROM actual_state s),
 'workTotal',(SELECT count(*) FROM atlas.work_items w WHERE w.organization_id=p.org_id),
 'sourceWorkTotal',(SELECT count(*) FROM atlas.work_items w
       WHERE w.organization_id=p.org_id AND w.source_object_type='rhythm_state'
         AND w.source_object_id=p.rhythm_id),
 'legacyTaskTotal',(SELECT count(*) FROM atlas.tasks t WHERE t.organization_id=p.org_id),
 'plannedOccurrenceTotal',(SELECT count(*) FROM atlas.planned_work_occurrences o
       WHERE o.farm_id=(SELECT s.farm_id FROM actual_state s)),
 'governedOfferTotal',(SELECT count(*) FROM atlas.governed_prework_candidate_offers_v1 o
       WHERE o.organization_id=p.org_id),
 'workAllocationTotal',(SELECT count(*) FROM atlas.work_allocations a WHERE a.organization_id=p.org_id),
 'workPlanTotal',(SELECT count(*) FROM atlas.work_execution_plans pl WHERE pl.organization_id=p.org_id),
 'workResultTotal',(SELECT count(*) FROM atlas.work_execution_results r
       WHERE r.organization_id=p.org_id),
 'originalResultTotal',(SELECT count(*) FROM atlas.work_execution_results r
       WHERE r.organization_id=p.org_id AND r.work_item_id=p.work_id),
 'originalAcceptanceTotal',(SELECT count(*) FROM atlas.work_result_acceptances a
       WHERE a.organization_id=p.org_id AND a.work_item_id=p.work_id
         AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'),
 'satisfactionTotal',(SELECT count(*) FROM atlas.rhythm_satisfactions s
       WHERE s.organization_id=p.org_id AND s.rhythm_state_id=p.rhythm_id),
 'principalObligationTotal',(SELECT count(*) FROM atlas.owner_obligations),
 'campaignTableAbsent',pg_catalog.to_regclass('atlas.governed_seasonal_scheduler_campaigns_v1') IS NULL,
 'campaignOfferTableAbsent',pg_catalog.to_regclass('atlas.governed_seasonal_scheduler_campaign_offers_v1') IS NULL
)::text AS snapshot
FROM requested p;
