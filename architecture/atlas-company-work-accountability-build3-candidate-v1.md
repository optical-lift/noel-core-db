# Atlas Build 3/5 — Company Work accountability read, scoped candidate

**Date:** 2026-10-17. **Source owner:** `optical-lift/noel-core-db`. **State:** source candidate only; not merged, not released, not consumed by Atlas notebook.

## Reality artery and source findings

`atlas.work_items.id` is the Company Work identity. `atlas.work_allocations` records exact responsible allocations; institutional positions and native Ledger seats do not create these allocations. `atlas.work_execution_plans` holds manager timing; `atlas.work_execution_plan_events` preserves planning changes and rollovers. `atlas.worker_week_projection` with `atlas.worker_week_projection_sources` is a *delivery carrier*, not receipt of viewing and not an Execution Lease. `atlas.work_execution_results` and `atlas.work_result_acceptances` establish separate reported-versus-accepted truths. Native Ledger relevance is defined *only* by Build 1's `atlas.company_work_native_ledger_relevance` with current source proof or owner attestation; neither Organization nor operating unit implies it.

Read-only live audit on 2026-10-17: 154 Company Work, 164 allocations (16 active/113 released/35 completed), three execution plans (all completed), 17 results, 105 week projections, 54 projection-source associations, 42 legacy day placements, zero transfer offers and **zero proven Work/native Ledger attributions**. Among week projections, 51 have `source_kind=work_item`, but **none** has the canonical `delivery_payload.projectionAuthority=work_execution_plans` marker. There were zero presently time-active `atlas.execution_leases` (all 22 observed leases were historical or non-current). These counts describe live observation, not fixtures or a promised post-release state.

Current `organization_management_plan_company_work_week_api_v1` calls `set_company_work_execution_plan_internal_v1`, which demands an active responsible allocation and lawful service date before planning. `set_company_work_responsibility_internal_v1` rejects selection-based imposition of responsibility without an established receiver-side basis. Current transfer offers remain pending until accepted. `carry_company_work_plan_after_elapsed_worker_day_v1` preserves `planned_service_date` and moves `exposure_service_date` with an event. Current `company_work_projection_result_reporting_self_v1` and `worker_report_company_work_projection_self_api_v1` gate reporting on self-scoped employee context, active allocation and matching active plan; `organization_decide_company_work_result_self_api_v1` retains separate institutional acceptance. Older `worker_week_projection` rows are not proof of present exposure or execution authority.

**Missing management read seam:** existing manager planning queue lacks an exact native Ledger accountability and reliable live projection versus worker report versus institutional acceptance distinction. It cannot safely be treated as proof that an employee has seen a planned line, nor can a manager impersonate a worker to call their self API.

## Bounded proposed kernel

`atlas.company_work_accountability_native_ledger_self_api_v1(organization_id,ledger_id,scope,limit,after_work_item_id)` is a **read-only owner-authorized projection**. Calls the current session/canonical Person/Principal/native seat/native and institutional root helper from Build 1. It does not invent delegated management authority.

Two explicitly distinguished scopes:
- `native_ledger`: only Company Work with **currently valid** evidence for this *exact* native Ledger, rechecking source-verified rows; owner attestation remains independent evidence.
- `organization`: institutionally owned Company Work under a separately labeled Organization lens, including items whose selected native Ledger relevance is not established. It is never presented as native Ledger inventory.

Returned dimensions: canonical Work identity, institutional custody, current exact responsible allocation and establishment basis, open transfer-offer count, plan/dates/history/conflicts/source window, observed canonical versus legacy/unverified worker projection, latest worker report, acceptance for that exact result. Dates are preserved separately; there is no invented universal priority or worker-view receipt. A projection is not labeled an execution warrant, not labeled viewed, and not a self-authenticated Worker Day read. No worker private data is queried or returned.

The role boundary is intentionally narrow. Root owner can inspect these institution-owned facts. Native seat alone, other Organization, invalid session, and unknown Ledger are denied. No manager/delegate or agency-client visibility is inferred here; Optical Lift internal Work must remain separate from published client commitments.

## Truth/state matrix for Build 4 callers

| Independent dimension | Canonical source | Safe present-tense interpretation | Must not imply |
| --- | --- | --- | --- |
| Institution custody | `atlas.work_items.organization_id` | Source Work belongs to exact institution | Native Ledger purpose |
| Native Ledger relevance | Active `atlas.company_work_native_ledger_relevance` with attestation/current source verification | Exact selected native Ledger association is established | Other Ledgers are excluded, or multiple task identities exist |
| Worker identity | Active `work_allocations` and explicit Person/IPR references through the exact membership | Actual same human carries this precise Work allocation | Person holds every Organization/Ledger hat or has a login |
| Offered transfer | `company_work_responsibility_transfer_offers` | Pending proposed handoff only | Responsibility accepted by target |
| Plan | `work_execution_plans` and `work_execution_plan_events` | Manager-selected planned service date, exposure date and rollover/history | Current Work is visible to worker |
| Delivery carrier | Matching `worker_week_projection` / `worker_week_projection_sources`, tied to Work, member, plan and date | A canonical planned projection is observed, or older unverified related carrier is observed | Worker opened/viewed it or has a current warrant |
| Viewing acknowledgement | No corresponding released view-receipt source proved | Explicit **not proven** | Receipt inferred from projection or past plan |
| Execution authority | Separate `execution_leases` and lease events, requiring live source contract and recipient/date proof | The owner projection intentionally does not assert an execution warrant merely from worker projection | Planning equals warrant |
| Worker report | Latest `work_execution_results` | Worker/source reported `blocked`, `unable`, `partial`, `completed`, etc. | Report accepted |
| Institutional acceptance | Exact `work_result_acceptances` for the reported result, plus Work lifecycle | A permitted policy/decision accepted/rejected the exact report | A manager performed worker-only reporting |
| Timeliness | `work_time_contracts` and `work_planning_conflicts` | Date bounds and unresolved planning conflicts are sourced | Universal invented urgency/importance score |
| Priority | No universal canonical Company Work priority across domains | `sortPriorityNotInvented=true`; clients can sort established dates and source attributes | Guess a numerical score from title/worker |

### Access and action matrix

The new accountability RPC is **read-only root-owner scope**, with exact Organization + native Ledger + Principal + seat + session proof. The existing `organization_management_company_work_planning_queue_api_v1` and `organization_management_plan_company_work_week_api_v1` have narrower, independently governed management authority. Their access is **not** implied by the new owner read; missing manager-wide rights stay pending.

The existing `organization_owner_set_company_work_responsibility_api_v1` is not an unrestricted assignment shortcut: its deeper responsibility kernel rejects imposing exact responsibility without a lawful receiver-side establishment basis. Existing transfer offers, responses and revocations are independent, and no transfer becomes active until uptake. Existing plan/clear and institutional decision commands retain their own validation. `worker_report_company_work_projection_self_api_v1` remains **employee self only**, not callable on behalf of a worker by a manager. The Build 3 guard additionally requires **selected projection date equals the employee's current governed service date**; viewing future work remains permitted but future completion from that projection is denied.

### Filtering and ordering

Every row has exact selected Ledger and Organization scope, Work identity, title, operation class, state, allocated member/person, manager planned/exposure dates, time-contract bounds, planning conflicts, latest result and separate acceptance. These are safe client filtering keys. The API currently pages in deterministic Work UUID order and **does not yet provide a source-side sorted query by date, urgency or Person**. Build 4 must not describe the keyset page as a fully server-sorted management backlog; scalable multi-filter sorting remains a named source enhancement if required before the notebook ships. No source priority is invented.

### Precise remaining proof boundary

The synthetic worker test uses fully formed source-identical identity, appointment, seat, credential, responsibility and plan fixtures inside a rollback-only production-schema clone, then calls the **actual authenticated worker self-read and report RPCs**. It proves the read/report/acceptance contract without logging in as a real user. The Worker Day projection rows are synthetic fixtures; an entirely source-generated manager plan → worker refresh → delivery projection path, view receipt, current Execution Lease and real Anna sign-in remain separate acceptance gates. Do not describe a synthetic carrier fixture as real worker receipt or full product acceptance.

## Operations this tranche does **not** add

No allocations, new Work rows, native Ledger attributions, people, login identities, week plans, Worker Day refresh or delivery writes, completion submissions, result decisions, owner escalation, Personal Clock/capacity fields, or cross-organization publication. Existing source writers retain their current governed jurisdiction. Owner Work queue and native Ledger Work view must remain visibly different in Build 4.

## Verification and remaining gates

- Migration: `supabase/migrations/20261017190000_atlas_company_work_accountability_native_ledger_v1.sql`, transaction wrapped `BEGIN; ... COMMIT;`.
- Source-identical candidate: `candidates/atlas_company_work_accountability_native_ledger_v1.sql`.
- Rollback-only synthetic validator: `validation/migrations/20261017190000_atlas_company_work_accountability_native_ledger_v1.sql`, derived from the previously accepted Build 2 identity/session/ledger fixture and expanded for pre-attribution organization-versus-Ledger scope, two independent attested Ledgers sharing one Work ID, unauthorized seat/outsider/invalid session, and provenance/status non-collapse. All its synthetic setup is inside `BEGIN; ... ROLLBACK;`.
- Required before merge: current production-schema disposable clone, role-positive and denial-path validation, no new Atlas lint errors, source/validator byte review. The validator does **not** yet prove an executable current Worker Day because no accepted active execution-plan/projection pair was established in this narrow tranche.
- Merge and production database release are separate future authorizations. No direct production DDL or `apply_migration`.
- Remaining Build 3 development: explicitly governed execution-lease verification and source-safe current worker receipt/visibility distinction, positive planned→projection→worker reporting paths on synthetic current worker context, manager delegation beyond root, stale/invalid future/rollover tests. Then Build 4 can compose the notebook without inventing these states.

## Build 4 handoff (not yet authorized)

If and only if the source is validated, merged and protected-released, consume the above RPC through Atlas's governed server/application adapter. Render the `organization` lens as an institution-level accountability view and `native_ledger` as exact-attested/native-source-proven relevance; never silently use an Organization row for Flower or Venue Work. Use explicit `not_proven` UI for viewing/execution receipts. Do not present a source PR or green clone as a working production notebook.
