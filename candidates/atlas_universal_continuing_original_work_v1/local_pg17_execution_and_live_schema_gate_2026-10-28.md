# Atlas universal continuing original Work — RiverSong local execution and live-schema gate

**Date:** 2026-10-28  
**Custody:** Draft Noel PR #2362; `codex/atlas-universal-continuing-work-gate0-20261028`  
**Status:** 38/38 local synthetic PostgreSQL 17 checks PASSED; **NOT production-releasable**.  
**Evidence:** User supplied RiverSong/Postgres.app 17.11 Terminal transcripts for all four files below, each ending `DO / ROLLBACK`. No private Actions workflow or production writes.

## Completed tests (source-exact PostgreSQL execution, fictional support data)

| Source test file | Checks | Outcome |
| --- | ---: | --- |
| `manual_original_work_synthetic_sql_v1.sql` | 9 | PASS; original Work creation, duplicate prevention, source identity |
| `manual_care_actual_synthetic_sql_v1.sql` | 10 | PASS; partial/full Actual, guarded Result/acceptance, Rhythm satisfaction |
| `manual_governor_need_assignment_synthetic_sql_v1.sql` | 10 | PASS; observed Need, Person allocation, date, collisions and refusals |
| `manual_integrated_governor_to_actual_synthetic_sql_v1.sql` | 9 | PASS; source-exact owner+original+Actual+guards in one transaction |

No test fixture retained database changes. The helper and Result source functions themselves were imported from the draft sources. **Identity, native Ledger custody, subject disclosure, Person assignment, current-care projection and some table constraints/triggers were substituted with fictional test scaffolding.** The actual installed Atlas source enforcement was *not* exercised.

## Read-only production schema metadata inspection (2026-10-28)

Supabase Noel `zirqkouammpwxlqfbsvf` queried using read-only `information_schema` and `pg_catalog` statements only. No production candidate was installed, no production test data was written.

**Present with expected broad shapes:** `atlas.work_items`, `work_item_context_links`, `work_allocations`, `work_execution_plans`, `work_execution_plan_events`, `work_execution_results`, `work_result_acceptances`, `company_work_native_ledger_relevance`, `company_work_standing_assignment_scopes`, `care_observation_events`, `care_result_events`, `care_current_state`, `rhythm_state`, `rhythm_rules`, `rhythm_bindings`, `rhythm_satisfactions`, `weed_cards`, `mowing_area_state`, `growing_objects`, `farms`, `tasks`, and `planned_work_occurrences`. Source writer referenced columns inspected are present, including `work_items.stable_key`, metadata, Source ID, Ledger/organization custody, Person allocation basis, service-date columns, source observation, and physical condition projection.

**Existing helper signatures confirmed:** `atlas.current_person_id_v1()`, `company_work_native_ledger_owner_self_v1(uuid,uuid)`, `person_has_native_ledger_connection_v1(uuid,uuid,uuid)`, `has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)`, `person_original_work_identity_disclosed_self_v1(uuid,uuid,uuid,uuid)`, `assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)`, `care_strategy_allows_ordinary_weeding_v1(uuid,date)`, `rhythm_boundary_at_v1(timestamptz,integer,text,text)`, `rhythm_safe_uuid_v1(text)`.

The new writer, original Work primitive, and physical Result function are not yet installed as released APIs. The candidate retains deliberate `REVOKE ALL` for unverified client execution.

## Live-schema integration gates — not green yet

1. **Real installed triggers and constraints.** The local fake tables omitted installed `work_items` completion/projection triggers, `work_allocations` establishment/provenance checks, `work_execution_plans` validation, and `care_observation_events` projection. Metadata confirms all these already exist. For example, existing `guard_governed_company_work_completion_v1` requires accepted Result evidence and `complete_company_work_execution_plan_v1` closes the service plan. The source code appears designed to satisfy those contracts, but that is **not a runtime verification**. Run a disposable full production-schema clone, preserve these live triggers, test with transaction rollback.
2. **Native Ledger attribution on completion.** Live `project_completed_company_work_to_ledger_v1` fires on organization Work completion and creates a compatibility organization-Ledger projection. It has an explicit exemption for `ledger_occurrence_shared_work`, but not for new `continuing_care_actual_v1`. Prove the new Work's completion both succeeds and is attributed only to its authorized native Ledger; protect against leaking or mismapping the physical Subject through a legacy read path. Do **not** suppress the shared projection or add a blanket bypass without evidence.
3. **Real signed Person disclosure/authority and adversarial reads.** Local `auth.uid`, `current_person_id_v1`, `has_current_subject_disclosure_v1`, and `person_original_work_identity_disclosed_self_v1` were stand-ins. The live `care_current_state` and `rhythm_state` tables grant `authenticated` SELECT under RLS; this is not proof of exposure or safety. Exercise true JWT/Auth + REST signed governor, assigned Person, unconnected Person, exact spatial Subject condition, alternate reader pathways, withheld Bed 4 vs permitted Bed 3, reassignment/revocation. An HTTP 404 or absent RPC cannot count as an authorization denial.
4. **Standing-scope limitation.** Owner observed-Need writer explicitly requires `coverage_mode='ledger_all_work'`, accepted Person scope, and separate Subject identity+condition disclosure. The existing source allocation function itself supports other coverage kinds, but this draft writer does not. Verify that the real intended connected Person has a lawful accepted scope before calling it; no automatic scope widening, employee seat or invented worker assent.
5. **Legacy original collision and no calendar-generated work.** Real farm `atlas.tasks`, `planned_work_occurrences`, and Rhythm task-release paths must be tested with older active tasks. Governor writer is fail-closed when the same Need already has an active old task; resolve historical custody with an explicit authorized disposition, not a duplicate new original.
6. **API release boundary.** Only after the protected full-clone signed positive and negative cases have passed, review any explicit authenticated `EXECUTE` grants and end-user Today/Notebook visibility. Keep draft RPCs revoked for now. Do not deploy to Noel, create employee seats, add a competing Work store, or run private GitHub Actions before the user authorizes release.

**Conclusion:** The real drafted functions execute together on vanilla PostgreSQL 17 with modeled source relationships, but the decisive remaining step is **installed-schema + signed-Person verification**, not more synthetic passes. Keep draft PR open and avoid touching real Elm/Anna until that evidence exists.
