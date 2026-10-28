# Atlas Proper — Universal Continuing Need → Work → Result — Gate 0 source map

**Status:** source-read audit and executable diagnostic only. No new engine, migration, grants, task records, assignment, release or UI.  
**Source of user requirements:** `Atlas_Universal_Subject_Need_Rhythm_Work_End_to_End_Build_Handoff.md` (October 26) and owner correction on [Atlas #449](https://github.com/optical-lift/atlas/issues/449) (October 27/28).  
**Audit:** live `noel-core` / `zirqkouammpwxlqfbsvf`, October 28 UTC, plus current `optical-lift/atlas` and `optical-lift/noel-core-db` main and draft PRs.  
**Reproducible check:** [`architecture/diagnostics/atlas_universal_continuing_work_gate0.sql`](diagnostics/atlas_universal_continuing_work_gate0.sql). It is READ ONLY and reports *gaps*, not fabricated green tests.

## Governing accepted behavior

One durable Subject + persistent Need + governed time/condition/dependency trigger + one original Work occurrence + appropriate responsibility + exact allowed Work Focus/Today projection + first-party typed Result + source state/satisfaction + one next eligible serving **when warranted**.

This is **not** a Farm Care engine. Weeding and mowing are Organization-owned acceptance cases; Laundry is the non-Organization (Household) acceptance case; Event Work is a regression. A continuing Need is not a task backlog, a weekly window is not completion, a released legacy `atlas.tasks` carrier is not the original `atlas.work_items`, and delegated worker delay is not automatic Principal Clock admission.

## Source map — facts, not proposed duplicate architecture

| Universal responsibility | Verified live source | Verified present capability | Unproven or missing seam |
| --- | --- | --- | --- |
| Original Work identity | `atlas.work_items` | One table admits exactly one native custody of Organization or Household (XOR CHECK); unique stable keys separately by custody. 228 Organization originals, zero Household originals at audit. | No proven Household original from a real Need. No source-owned universal recurrence-to-Work writer. |
| Work ↔ real Subject | `atlas.work_item_context_links` | Typed subject links with Organization/Household XOR, multiple relations and stable Work ID; currently 35 temporal links. | Original index subject and linked-current Need/trigger reader not proven for Laundry / garden bed / Event across scopes. Signed field-visibility tests required. |
| Exact responsibility | `atlas.work_allocations` | Native Organization Person scope and independently Household carrier constraints; current source allows native Person allocations distinct from legacy employee seats. | Canonical conditional occurrence author+allocation for each context unproven; permission decisions must use governing signed operations. |
| Work schedule | `atlas.work_execution_plans`, `atlas.work_time_contracts`, Clock admissions | A working/service date is distinct from due-date; source keeps original Work ID. | Recurrence eligibility must not assign Today, mutate due date or Principal Clock without separate schedule/attention authorization. |
| Farm Need/condition | `atlas.growing_objects`, `atlas.weed_cards`, `atlas.mowing_area_state`, `atlas.care_current_state` | Physical Object, care observations and results exist; old routes have equipment/condition and legacy task history. | Farm observation freshness: existing eligible occurrences cannot automatically mean actual weeds/required mow; some areas are resting. Do not import old task state as source truth. |
| Farm Rhythm | `atlas.rhythm_rules`, `rhythm_bindings`, `rhythm_state`, `rhythm_satisfactions` | 98 weed and 5 mow state records, 251 historic rhythm satisfactions. `ensure_rhythm_task_v1`, `farm_rhythm_tick_v1` and `apply_result_rhythm_effects_v1` exist. | 0 of their current occurrences resolve to OPEN `work_items` via canonical occurrence source. `planned_work_occurrences` requires `farm_id`; `rhythm_state` requires `organization_id` and `farm_id`. These are **domain implementations**, not universal tenancy. |
| Household Need/condition | `atlas.world_kernel_definitions`, `atlas.household_kernel_instances`, `atlas.household_spaces`, `atlas.care_current_state`, `atlas.care_result_events` | Real Household World Kernel and care source records, signed `principal_record_household_care_result_api_v1`. At audit, zero Household care result events. | No confirmed canonical Work or result-to-rhythm satisfaction; do not invent home equipment/cadence or treat calibration as a protected requirement. |
| Household Rhythm | `atlas.household_rhythms`, `atlas.household_rhythm_tick_v1` | 21 active Household rhythms; window roller exists. | Window roll is **not** qualified Work completion or satisfied Need. Must not be rendered as autonomous new Today Work. |
| Original Results | `atlas.work_execution_results`, `atlas.work_result_acceptances`, domain `care_result_events` / `rhythm_satisfactions` | Canonical Work results, domain care results and rhythm satisfactions exist as separately attributable records. | Need one governed Work result → correct source state → satisfaction/continuation → next eligible Work bridge with no duplicate receipt. Domain result kinds remain typed; universal transition does not erase their meaning. |
| Event regression | Existing `ledger_occurrence_shared_work_self_api_v1` / `create_ledger_occurrence_shared_work_self_api_v1` / `mark_ledger_occurrence_shared_work_done_self_api_v1` | Event-attached canonical Work uses the same `work_items` table. | Continuation changes must not duplicate Event source and must preserve native Ledger privacy/authority. |
| Person Today | `connected_person_company_work_today_self_api_v1`; Atlas `CanonicalWorkFocus` and unified Today | Signed Company Work path exists, with independently governed exposure. | No universal Household + Organization source readback proof; exposing eligible Need does not by itself create a scheduled Today commitment. |

### Important correction to older handoff

The October 26 handoff reported `calibrate_personal_laundry_kernel_self_api_v1` invoked `principal_upsert_household_rhythm_api_v1` automatically. Its **current live function body no longer contains that call** as checked October 28. This is a source-level correction to the stale handoff, **not** evidence that end-to-end calibration, no-auto-rhythm side effects or Household result satisfaction are signed-tested. Do not regress that separation.

## The actual gap, in one seam

Current recurring farm data can produce `planned_work_occurrences` and `atlas.tasks` through farm-specific gates. Canonical Today instead requires source-authorized `atlas.work_items`, native responsibility, and real signed Work decisions. An adapter that merely draws a task card does not fix that gap, and granting an old `tasks` row authority would recreate the legacy system. Nor can `household_rhythms` be forced to carry a `farm_id`.

**Source design boundary for next implementation:** retain one original Work identity and result/assignment model, preserve domain-owned Subject state and policy, define a **typed, custody-scoped, idempotent continuation decision** (Need + rule evidence + condition + release gate) that can establish exactly one original Work serving via governed writer and react to a qualifying source result. Reuse `work_item_context_links`, `work_execution_results`, source-specific observation and existing Clock/Today readers. Do not create a second recurrence writer or physically move Household into Company.

## Exact acceptance gates

1. **Source truth:** a current observation/authorized override makes an action eligible; resting/stale states produce observation/reassessment or quiet status, not fabricated labor.
2. **Original Work:** one stable original per exact Need/occurrence, on Organization **and** Household contexts. Duplicate calls/Today refresh do not create another original.
3. **Native responsibility and schedule:** connected Person or Household member can lawfully take responsibility; unassigned Work remains findable; due date, service date and Today admission are distinct.
4. **First-party Result:** real original Work Focus captures full/partial/no action/blocked/more evidence with correct domain-specific meaning, actor and subject; cannot imply physical recovery from a generic checkbox.
5. **Continuation:** result writes authoritative domain facts and affects only the correct Need; it closes/continues that Work and determines one next eligible serving, without pre-generating future Work.
6. **Privacy and regression:** signed Anna/owner/unrelated Person + Household member/unrelated Person tests, old alternate-reader negatives, immutable result history, existing Event Work unchanged.
7. **Release:** source migration through Noel PR/approved clone and protected release; Atlas caller/Today deployed only after real approved source exists, RiverSong exact SHA and signed browser readback.

## Scope and collision control

- Atlas [#449](https://github.com/optical-lift/atlas/issues/449) now governs this universal priority. The historical ten-task transfer remains a separate archived decision stream, **not a prerequisite**.
- Noel draft [#2360](https://github.com/optical-lift/noel-core-db/pull/2360) and Atlas draft [#471](https://github.com/optical-lift/atlas/pull/471) are a different original Work **transfer** stream. Do not edit their branches or merge either to simulate recurring Work.
- No code, database permission, deployment, real Work, Household or farm observation is modified by Gate 0. The diagnostic is intentionally report-only.
- **Next source slice:** exact idempotent original-Work serving binding, with positive/negative synthetic validation in BOTH Organization and Household. Work-to-result qualification before presenting worker Today. No unilateral production release.

### Gate 0 verdict

**Partial foundational PASS** — one native Work table, both custody shapes, typed subject links and multiple functioning domain rhythm/result sources were verified. **Lifecycle FAIL / NOT IMPLEMENTED** — no confirmed result-connected original Work recurrence across either test context. CI/schema success is not signed end-to-end acceptance.