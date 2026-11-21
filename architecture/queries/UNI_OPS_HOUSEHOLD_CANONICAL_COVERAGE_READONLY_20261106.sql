-- UNI-OPS-01 U5: aggregate-only Household native → canonical coverage audit.
-- 2026-11-06 · READ ONLY · NOT authorization, migration, fixture, writer,
-- identity resolver, disclosure grant, Foundry approval or Rulebook admission.
-- No IDs, private observations or Household contents in output.
-- A true coverage flag would STILL NOT grant policy/Work authority.
WITH counts AS (
 SELECT
 (SELECT count(*) FROM atlas.households WHERE status='active') AS active_households,
 (SELECT count(*) FROM atlas.household_kernel_instances WHERE state='active') AS active_household_kernel_instances,
 (SELECT count(*) FROM atlas.care_observation_events WHERE scope_kind='household' AND subject_domain='household' AND inferred_from_clock=false AND observed_by_user_id IS NOT NULL) AS firsthand_household_observations,
 (SELECT count(*) FROM atlas.household_need_occurrences_v1 WHERE state='open' AND opened_by_observation_id IS NOT NULL) AS open_observed_household_needs,
 (SELECT count(*) FROM reality.entities WHERE identity_state='canonical' AND metadata->>'subjectDomain'='household') AS declared_household_canonical_entities,
 (SELECT count(*) FROM atlas.work_requirements w JOIN reality.entities e ON e.id=w.source_object_id WHERE w.state='active' AND w.source_object_type='reality_entity' AND e.identity_state='canonical' AND e.metadata->>'subjectDomain'='household') AS active_household_canonical_requirements,
 (SELECT count(*) FROM atlas.identity_reconciliation_adjudications) AS atlas_identity_adjudications
)
SELECT *, (firsthand_household_observations>0 AND open_observed_household_needs>0 AND declared_household_canonical_entities>0 AND active_household_canonical_requirements>0) AS raw_prerequisite_coverage_only_not_admission FROM counts;
