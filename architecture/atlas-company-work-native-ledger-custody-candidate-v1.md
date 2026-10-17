# Atlas Company Work → Native Ledger custody — candidate v1

**Source status:** review-only proposal in `candidates/`. NOT a canonical timestamped migration, NOT a released RPC, NOT deployed to Supabase. Owner authority decisions and clone acceptance are gates. App notebook, People and scheduling are out of scope.

## Verified October 17, 2026

- `atlas.work_items` owns one Company Work identity with `organization_id` and `organization_unit_id`; it has no native Ledger FK.
- `ledger.ledgers` owns native notebook Ledgers. `atlas.ledgers` is the older institutional compatibility graph. The matching native/legacy Ledger UUIDs for the current three examples are **not** proof of work membership.
- `atlas.ledger_organization_participations` verifies institutional Ledger participation. Elm Flower and Elm Venue participate in Elm Farm, Optical Lift's agency Ledger in a separate Organization. Participation does **not** attach any particular Work item.
- `atlas.work_item_context_links` only permits identity and spatial context; current row count zero. `atlas.ledger_correlations` row count zero.
- Live `atlas.work_items`: 154 rows, all under Elm Farm Organization. Elm operating unit: 151 (77 open, 55 completed, 19 cancelled). Waiting Room operating unit: 3 (1 open, 2 completed). Neither operating-unit key establishes native Ledger membership. No current evidence-backed Work→native-Ledger relation was found.

## Legal custody

**Owning Organization ≠ Operating Unit ≠ Native Ledger ≠ Ledger relevance.**

Company Work has one institution and one stable `work_item_id` regardless of assignment, Worker Day or result. A positive, source-attested association says that work serves a specified native Ledger purpose; one Work ID may serve two Ledgers without duplicate work, allocation or completion. No association means **unknown**, not 'does not belong'. One established Ledger link does not automatically exclude other Ledgers.

Candidate v1 accepts only a signed-in root Principal's explicit designation (`owner_attestation`) with a retained `sourceRef`. A verified source-object binding (`source_binding`) is **not** admitted until an actual source-owned foreign-key resolver and its tests exist; a text reference alone is not verified source evidence. Names, titles, NLP guesses, legacy work type, operating-unit label or general Organization participation are never adequate proof.

The candidate permits associations only when a native Ledger is active, is matched by the legacy Ledger ID, and has current **governing/operating** participation in the owning Work Organization. It does not infer a relationship from that eligibility.

The initial guarded command requires a valid Atlas session, canonical Person/Principal, current native seat, root authority over the selected native Ledger, and root authority over the Organization's unique primary governing Ledger. It is deliberately **owner-only**; expansion to other managers, workers and delegates awaits the People authority stage. A seat is not ownership. Direct table access is denied. Withdrawal preserves the original evidence and actor.

## Proposed source contract

- `atlas.company_work_native_ledger_relevance`: explicit native Ledger relevance with immutable original evidence, active/withdrawn lifecycle and per-pair active uniqueness.
- `atlas.guard_company_work_native_ledger_relevance_v1()`: validates source Organization and native Ledger eligibility, guards identity/history.
- `atlas.company_work_native_ledger_owner_self_v1(organization_id,ledger_id)`: private authority check.
- `atlas.establish_company_work_native_ledger_relevance_self_api_v1(work_item_id,ledger_id,evidence_basis)`: only explicit owner-attested/source-attested positive links; idempotent for existing active pair.
- `atlas.withdraw_company_work_native_ledger_relevance_self_api_v1(attribution_id,reason)`: reasoned withdrawal, no task deletion.
- `atlas.company_work_native_ledger_scope_self_api_v1(organization_id,ledger_id,limit,after_work_item_id)`: owner-scoped direct matches, source evidence and Organization-wide unattributed count; no other Organization data.

## Source mapping

| Evidence | Result |
|---|---|
| Exact native-Ledger FK on the source obligation and authorized establishment | NOT YET IMPLEMENTED — a source-specific resolver must validate the actual FK before admitting `source_binding` |
| Owner explicitly judges one existing Elm work obligation relevant to Flowers | Attested relevance link to Flowers; no change in task owner |
| One Elm obligation really serves Flowers and Venue | Two relevance links, **one** original work ID |
| Generic Elm unit, old task, marketing/flowers/venue words in title | `unknown`; review candidate only |
| Previous attribution wrong | Withdraw link with reason; work and history stay unchanged |
| Agency employee's task in Optical Lift serving Elm | Optical Lift owns its internal work. Elm requires a separate, authorized external service commitment/result publication seam; never gets the agency's internal work merely by adding a second Ledger link |

All 154 existing Work rows remain pending exact Ledger attribution; no destructive or speculative backfill is permitted. In particular, three Waiting Room records under the Elm Farm Organization must not be silently included in either native Elm Ledger.

## Source → approval → release

1. Review the two authority decisions: whether **root owner + selected native seat + institution's governing root** is the initial allowed attribution writer, and whether a human's explicit, recorded `owner_attestation` is sufficient to designate work relevance while actual source FK verification remains blocked.
2. In `noel-core-db`, inspect current main and domain-custody rules; promote only approved candidate SQL to a fresh `atlas_` canonical timestamped migration using the repo's governed release workflow.
3. Validate in disposable schema clone, including authenticated positive and negative fixtures. `candidates/atlas_company_work_native_ledger_relevance_v1_validation.sql` checks minimal structural invariants; it does **not** replace identity/privacy acceptance. Run security advisors, migration reconciliation and `atlas_` lane CI.
4. Release through protected manual DB process; record migration version, hashes and live RPC signatures. No Atlas Preview/Production deployment is implied or permitted by a source merge.

## Conversation 2 handoff — CONDITIONAL

Only once v1 is *released* may People use `organization_id`, `organization_unit_id`, `work_item_id`, native `ledger_id`, evidence class and the governed role-scoped read. The stage does not create People records, agency employment, cross-company exposure, Worker Day projection, scheduling or UI. On the audit date, unknown Work=154 (Elm unit 151; Waiting Room unit 3). Root-only command is not a manager/delegate policy. No assignment, source obligation, result, notebook or production data was changed by source-candidate work.
