# Atlas Exact Work Responsibility Writer Classification v1

**Status:** Current-canon implementation map  
**Established:** September 20, 2026  
**Governing contract:** `atlas-exact-work-responsibility-establishment-current-canon-v1.md`

## Purpose

Classify every current `atlas.work_allocations` writer/caller before introducing an establishment-basis seam.

The classification answers:

> Is this writer entitled to create active exact-work responsibility, and if so, why?

This document does not mutate schema or production state.

## Current writer map

| Writer | Creates `responsible`? | Classification | Current-canon disposition |
| --- | --- | --- | --- |
| `add_institutional_conversation_collaborator_self_api_v1` | No; participant/approver only | collaboration, not responsibility | preserve; outside responsibility-establishment repair |
| `claim_institutional_conversation_self_api_v1` | Yes | explicit self uptake | preserve; migrate to explicit `self_claim` basis |
| `ensure_outbound_conversation_responsibility_service_v1` | Yes | self-originated consequence / self uptake | preserve; migrate to explicit `self_initiated_outbound` basis |
| `create_communication_derived_work_self_api_v1/v2` | Yes when assignee supplied | mixed: self uptake when assignee=actor; false cross-Person assignment when assignee!=actor | allow unassigned + self uptake; cross-Person assignee must fail closed / become offer |
| `handoff_institutional_conversation_self_api_v1` | Yes | cross-Person transfer without receiver uptake | stop immediate responsibility transfer; future responsibility offer/acceptance |
| `handoff_communication_derived_work_self_api_v1` | Yes | cross-Person transfer without receiver uptake | stop immediate responsibility transfer; future responsibility offer/acceptance |
| `organization_owner_set_company_work_responsibility_api_v1` | Yes | owner selection only | fail closed as generic responsibility creation; owner may route/propose, not assign |
| `ensure_weekly_harvest_company_work_v1` | Yes | transitional legacy occurrence reconstruction/adoption | preserve narrowly while legacy weekly-harvest carrier exists; do not generalize |
| `sync_explicit_worker_task_company_work_v2` | Yes | transitional legacy task reconstruction/adoption | preserve narrowly while legacy task carrier exists; do not generalize |
| `set_company_work_responsibility_internal_v1` | Yes | low-level storage mechanism | not an authority source; migrate truthful callers to a versioned basis seam before retirement |

## Live production evidence

At audit time, production had:

- 20 active exact `responsible` allocations;
- 12 active allocations from `explicit_worker_task_company_work_adoption_v2`;
- 7 active allocations from `owner_week_plan_2026_09_13`;
- 1 active allocation from `legacy_weekly_harvest_occurrence_assignment`;
- zero active allocations sourced by `organization_owner_set_company_work_responsibility_api_v1`;
- zero active allocations sourced by `create_communication_derived_work_self_api_v1`.

The two legacy farm adapters are still reachable indirectly through database trigger/sync functions even though no current default-branch application code calls them directly.

Therefore they are compatibility machinery with live effects, not safe retirement targets in the first slice.

## First implementation slice

The first executable repair should change only the false cross-Person paths while preserving live compatibility adapters.

### Preserve

- self claim;
- self-originated outbound follow-up;
- participant/approver collaboration;
- existing historical allocations;
- weekly-harvest legacy reconstruction adapter;
- explicit-worker-task legacy reconstruction adapter.

### Change

#### Owner direct assignment

`organization_owner_set_company_work_responsibility_api_v1` must no longer create a new active responsible allocation for another member from owner selection alone.

Keep the signature fail-closed for stale callers until Product has a responsibility-offer surface.

#### Communication-derived Work creation

Creating Work remains valid.

- no assignee → create unassigned Work;
- assignee is authenticated actor → explicit self uptake may create responsibility;
- assignee is another member → do not create responsibility; fail closed or return establishment-required.

Endpoint `handoff` is routing authority, not receiver uptake.

#### Handoff functions

`handoff_institutional_conversation_self_api_v1` and
`handoff_communication_derived_work_self_api_v1` must stop directly replacing the responsible allocation.

Until a responsibility-offer/acceptance seam exists, cross-Person handoff must fail closed rather than fabricate acceptance.

The current responsible allocation must remain active when transfer is merely proposed/attempted.

## Versioned establishment seam

Do not mutate the v1 internal writer signature first.

Introduce a versioned internal writer conceptually shaped as:

```text
set_company_work_responsibility_with_basis_internal_v2(
  work,
  assignee,
  actor,
  establishment_basis_kind,
  establishment_basis_ref / evidence,
  reason,
  provenance
)
```

Initial admitted basis kinds should be only those current source can actually prove, such as:

- `self_claim`;
- `self_adoption`;
- `self_initiated_outbound`;
- `legacy_governed_reconstruction`.

Do **not** admit placeholders for:

- standing intake before an executable agreement exists;
- relation-constituted exact work before a bounded applicability rule exists;
- accepted transfer before receiver acceptance exists.

Unknown basis fails closed.

## Legacy compatibility adapters

### Weekly harvest

`ensure_weekly_harvest_company_work_v1` currently reads an assignee from the transitional planned occurrence and mirrors it into exact Work responsibility.

This is allowed only as a bounded legacy reconstruction/adoption adapter for the named weekly harvest carrier.

It must not become a generic rule that:

```text
legacy carrier assignee -> canonical responsibility
```

for new domains.

### Explicit worker task sync

`sync_explicit_worker_task_company_work_v2` currently adopts top-level legacy worker tasks into Company Work and can preserve/change the responsible allocation from the legacy task assignee.

This remains transitional compatibility because production still contains active allocations sourced from it.

Its retirement target is removal of the legacy task carrier as responsibility evidence, not promotion into the generic responsibility seam.

## Historical owner-week-plan rows

The seven active `owner_week_plan_2026_09_13` allocations are preserved.

Anna's current durable Farm Steward relation includes:

- Grounds readiness;
- Harvest execution;
- Nursery care;
- Production stewardship;
- Venue preparation;

all scoped to the Elm Organization Unit.

That durable relation may explain some historical exact allocations, but broad Organization Unit Scope does not prove every exact Work assignment.

Do not retroactively invent establishment evidence.

Future owner planning may record routing/schedule recommendations without creating responsibility.

## Required first-repair proof

A production-schema clone for the first responsibility-establishment repair should prove:

1. self claim still creates responsibility for the claimant;
2. self-originated outbound follow-up still creates/retains responsibility for that actor;
3. communication-derived Work can be created unassigned;
4. communication-derived Work can be self-adopted;
5. communication-derived Work cannot assign another member from `handoff` capability alone;
6. owner selection cannot directly create another member's responsibility;
7. conversation handoff cannot directly replace the current responsible member;
8. derived-work handoff cannot directly replace the current responsible member;
9. failed cross-Person handoff leaves current responsibility unchanged;
10. the two live farm compatibility adapters continue to function unchanged;
11. participant/approver collaborator allocations remain unaffected;
12. historical allocation rows are untouched.

## Next step

Implement the versioned establishment-basis seam and migrate only truthful self-uptake callers first.

Do not build the generic Responsibility Offer kernel until the fail-closed boundary is in place.
