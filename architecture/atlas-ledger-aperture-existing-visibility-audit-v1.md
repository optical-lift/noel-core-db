# Atlas Ledger Aperture — Existing Visibility Audit v1

**Status:** Architecture audit only
**Date:** 2026-09-14
**Executable scope:** None

## Purpose

Audit the visibility mechanisms already present in `noel-core` against the Ledger Aperture rule that visibility and responsibility are completely independent.

This audit does not create a replacement visibility model. It identifies which current mechanisms are semantically admissible evidence, which are domain-local, and which are compatibility behavior that the future generic aperture resolver must not reinterpret as canonical visibility.

## Governing decision

From `atlas-ledger-aperture-visibility-independence-v1.md`:

> Responsibility never creates visibility, including visibility to the responsible subject itself.

Therefore a generic aperture resolver may admit visibility only from a contract whose meaning is actually visibility/read exposure. Assignment, responsibility, placement, title, role, seat, credential, or delivery state cannot substitute.

## Existing visibility/exposure mechanisms found

### 1. `organization_member_exposure_grants`

Current shape:

- organization-scoped;
- organization-membership-scoped;
- optionally tied to an `organization_employee_seat`;
- grants an `information_class`;
- carries a coarse `scope_kind` of `assigned_work`, `related_work`, `team`, or `organization`;
- records grantor membership and provenance.

Current allowed information classes are worker-oriented:

- `worker_delivery_identity`
- `worker_execution_context`
- `worker_coordination_context`
- `worker_institutional_intelligence`

Semantic value:

- proves that Atlas already treats information exposure as an explicit institutional act;
- proves that exposure is distinct from responsibility and mutation authority;
- is valid compatibility evidence only within the exact organization/member/seat contracts that currently govern it.

Limitation:

- it is not a generic Person + Ledger visibility relation;
- its information classes and scope kinds are worker-specific;
- the active production table currently contains no grant rows;
- it must not be silently generalized merely because its shape resembles the future need.

### 2. `semantic_exposure_policies` + `semantic_exposure_envelope_v1`

The existing semantic exposure membrane requires all of the following before admitting a candidate:

- active organization membership;
- active paid/waived employee seat;
- supported worker-facing purpose;
- matching active member exposure grant;
- matching semantic exposure policy;
- typed candidate validity and, for claims, admitted evidence/adjudication state.

This is strong evidence for the architectural principle that **policy eligibility and person-specific exposure are separate checks**.

However, it is explicitly organization-member/employee-seat/worker-purpose shaped. It is therefore a compatibility membrane, not yet the generic Ledger visibility resolver.

Current production policies are narrowly scoped to employer-drawer event/harvest facts. There are currently no production member exposure grants to satisfy the person-specific grant side.

### 3. Communication endpoint member grants

`communication_endpoint_member_grants` records member-specific capabilities over communication endpoints.

This is domain-specific governed visibility/capability evidence for correspondence. It should remain owned by the communication domain and may contribute to a future aperture only through a governed mapping from endpoint/conversation custody to the queried Ledger and through the communication contract's exact semantics.

It is not a universal Ledger visibility grant.

### 4. Domain `visibility_scope` columns

Several older/domain tables contain `visibility_scope` or similarly named columns, including tasks, goals, rhythm state/transitions, journal indexes, and addressable interfaces.

A column name containing `visibility` is not enough to make it generic aperture evidence.

Each such field must be evaluated against the contract that created it:

- what subject is being hidden/exposed;
- to which audience;
- whether the value is descriptive metadata or an authorization boundary;
- whether it resolves to the queried Ledger under effective custody;
- whether another stronger canonical visibility contract supersedes it.

No generic resolver may union these columns merely by name.

## Existing compatibility behavior that violates the future semantic rule

### `worker_day_visibility_floor_v1`

This function currently produces task visibility from worker assignment/due-date/placement facts. Its candidate logic includes legacy carriers such as:

- `tasks.assigned_membership_id`;
- `tasks.assigned_user_id`;
- executor metadata;
- worker key/assignee metadata;
- explicit Worker Day placement;
- task dates.

Under Ledger Aperture v1, those are not independent visibility grants.

Therefore:

> `worker_day_visibility_floor_v1` is a compatibility Worker Day projection and must not be admitted as generic visibility evidence in `resolve_effective_ledger_aperture`.

This audit does not remove or alter it.

### `worker_day_work_projection_v1`

This projection marks selected/placed assignment-matching tasks as `visible` after execution-readiness checks.

That remains valid only as current legacy Worker Day behavior. Its `visibility_state='visible'` output cannot be promoted into the future generic Ledger aperture merely because the column is named visibility.

### Worker self APIs

Current worker self APIs still authorize the surface using legacy facts such as:

- authenticated user;
- active `farm_hand` farm membership;
- organization membership role;
- employee seat;
- credential;
- active position appointment.

Those facts currently protect the compatibility product surface. They are not, individually or collectively, the future semantic proof that the Person may see a particular piece of Ledger reality.

## Current conclusion

There is **no existing generic canonical visibility substrate** that can answer:

> For Person P and Ledger L, which specific Ledger reality may P know?

Existing visibility mechanisms are either:

1. worker/employee-seat compatibility exposure;
2. domain-local grants/contracts;
3. legacy task/placement visibility behavior;
4. descriptive visibility metadata whose authorization meaning is domain-specific.

Accordingly, the first executable generic aperture resolver cannot truthfully implement its visibility dimension by re-labeling an existing role, responsibility, assignment, seat, or Worker Day visibility function.

## Safe migration rule

Until a generic visibility model is explicitly situated:

- preserve existing surface-specific visibility behavior as compatibility behavior;
- do not broaden it;
- do not normalize assignment into visibility;
- do not normalize responsibility into visibility;
- do not claim a generic Person/Ledger visibility answer where no canonical source exists;
- allow a future aperture resolver prototype to return `visibility: unresolved/not_yet_generic` rather than fabricating a grant.

## Decision required before executable generic visibility work

A new architectural decision is required before creating any generic Ledger-addressed visibility relation or resolver behavior.

The unresolved question is not whether visibility is separate from responsibility; that is settled.

The unresolved question is **what kind of truth a generic visibility grant is and where it should live**.

No schema, RPC, grant, or production behavior is created by this audit.
