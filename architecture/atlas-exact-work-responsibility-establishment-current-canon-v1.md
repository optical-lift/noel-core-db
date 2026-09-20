# Atlas Exact Company Work Responsibility Establishment — Current Canon v1

**Status:** Governing architecture for the second Authority Dimensions repair  
**Established:** September 20, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**Depends on:** atlas-authority-dimensions-current-canon-v1  
**Does not rewrite:** existing historical `work_allocations`, durable institutional responsibility, or execution-warrant law.

## 1. Purpose

Atlas already separates:

- durable institutional responsibility;
- exact Company Work responsibility;
- present execution warrant.

The remaining defect is not the storage of exact Work responsibility. `atlas.work_allocations` remains a truthful carrier for:

> Who currently carries responsibility for this exact Company Work item?

The defect is **how a new active responsible allocation may be established**.

Current compatibility commands can still perform the false move:

```text
owner / planner / sender selects Person
→ active responsible allocation exists
```

That is not a universal responsibility law.

This contract makes the establishment basis explicit without replacing `work_allocations`.

## 2. Governing law

> **An active exact-work responsibility must be explainable by the governing relationship that made that exact response belong to the Person. Selection, visibility, planning authority, handoff capability, membership, title, and technical write access are not sufficient establishment bases by themselves.**

The accepted basis families are:

1. **assumed item responsibility** — the Person explicitly takes up this exact Work;
2. **standing-intake responsibility** — prior bounded assent admits this exact Work;
3. **relation-constituted exact responsibility** — an explicit domain/relationship rule establishes that this exact Work already belongs to the Person;
4. **reconstructed/adjudicated responsibility** — Atlas records that the Person already carried this exact responsibility before the current allocation row;
5. **self-adopted responsibility** — the Person deliberately takes responsibility for Work they are authorized to adopt, which is a form of receiver uptake.

No other basis is implied merely by actor power.

## 3. Durable institutional responsibility is context, not exact allocation

Current Organization structure can truthfully establish that a Person carries durable responsibilities such as:

- Production stewardship;
- Harvest execution;
- Nursery care;
- Grounds readiness;
- Venue preparation.

Those durable relations are bounded by Organization Responsibility and Responsibility Scope.

They do **not** imply:

```text
every current/future Work item in the Organization Unit
→ allocated to that Person
```

For a durable relation to establish an exact Work item automatically, Atlas must have an explicit, bounded **applicability rule** proving that the Work falls inside a responsibility effect that itself establishes exact carriage.

The following are insufficient on their own:

- same Organization Unit;
- matching human-language title;
- broad responsibility name;
- role/member/owner labels;
- Work operation class that merely sounds related.

## 4. Relation-constituted exact Work requires an applicability rule

A future relation-constituted resolver must be able to explain:

```text
effective Person↔institution responsibility R
+ bounded responsibility Scope S
+ exact Work W
+ governed applicability rule A
+ no material conflict
→ W is already-binding exact responsibility of Person P
```

The applicability rule may be domain-specific.

Examples that could eventually be valid:

- a recurring Harvest occurrence whose governing rule explicitly says the current Harvest Execution carrier owns that occurrence;
- a specific statutory/on-call duty tied to an active appointment;
- a previously accepted commitment that deterministically produces exact child Work.

Examples that are **not** valid merely by resemblance:

- `Grounds readiness` therefore every maintenance task;
- `Production stewardship` therefore every farm operation;
- `Farm Steward` therefore every Elm Work item.

Ambiguity fails closed.

## 5. Assumed exact Work

Where the exact Work is a new optional undertaking, the Person must take it up through:

- item-level acceptance; or
- a matching active standing responsibility-intake agreement.

Current architecture already defines both semantics, but no generic executable standing-intake kernel exists yet.

Therefore a current writer must not pretend that standing intake exists merely because employment/position evidence exists.

Until the executable intake basis is present, cross-Person optional Work must remain:

- unassigned / awaiting uptake; or
- represented through a domain-local offer/claim path that already truthfully records uptake.

## 6. Owner and management planning authority

An Organization owner or manager may lawfully:

- create Company Work;
- prioritize it;
- schedule it;
- expose it to eligible participants;
- propose a responsible Person;
- establish a responsibility offer;
- adjudicate institutional facts where separate management-adjudication authority applies.

That does **not** mean:

```text
owner selected member
→ member responsibility exists
```

The current `organization_owner_set_company_work_responsibility_api_v1` is therefore compatibility behavior, not a constitutional responsibility-establishment primitive.

## 7. Handoff authority

Handoff authority answers:

> May this actor initiate/perform the governed responsibility-transfer process?

It does not mean:

> May this actor make the target Person responsible without the target-side establishment rule?

For a new receiver, handoff needs an effect-specific basis:

- accepted carrier transfer;
- accepted delegated child responsibility;
- accepted/shared participation;
- another already-binding relation rule.

Current domain-local handoff operations may remain where they already contain truthful uptake semantics. A generic `handoff` capability is not itself receiver uptake.

## 8. Communication-derived Work collision

Current `create_communication_derived_work_self_api_v1` can:

- create exact Company Work from a Communication Event;
- accept a target Organization Membership;
- if the target is another member and the actor has Endpoint `handoff`, call the generic responsibility writer immediately.

That collapses:

```text
may route / handoff Communication work
→ may create receiver responsibility
```

The future repair must separate:

```text
create Work
→ optionally propose receiver / offer responsibility
→ receiver uptake or other lawful basis
→ active responsible allocation
```

Self-adoption may remain immediate when the actor selects themselves and all other Work-creation authority is valid, because the receiver and actor are the same Person and the command is the uptake act.

## 9. Existing live allocations are not rewritten by this contract

Production currently contains active exact Work allocations from several historical carriers, including:

- explicit worker-task adoption;
- owner week planning;
- legacy harvest assignment.

The current owner direct-assignment API accounts for zero active allocations, and current Atlas app source contains no caller for that API.

Some historical allocations may correspond to valid relation-constituted or previously agreed work; others may be compatibility debt.

This contract does not retroactively release them.

Historical convergence should preserve:

- what Atlas currently treats as responsibility;
- original allocation provenance;
- uncertainty about establishment basis where the historical evidence is insufficient.

Do not rewrite history to make present architecture look cleaner.

## 10. Responsibility establishment provenance

Every future creation of an active `allocation_role='responsible'` row should preserve an establishment basis sufficient to answer:

- what basis family established the responsibility?
- who/what supplied that basis?
- what exact Work was established?
- who is the responsible membership/Person?
- when did the responsibility become effective?
- if based on durable responsibility, what applicability rule linked the exact Work?
- if based on standing intake, which agreement admitted the offer?
- if based on acceptance, what receiver act accepted it?
- if reconstructed/adjudicated, what evidence/adjudication established prior carriage?

The first implementation does not require a universal responsibility-relation table.

A bounded basis envelope on exact-work allocation creation may be sufficient until multiple domains prove a shared executable offer/intake kernel.

## 11. First implementation direction

Before building a generic Responsibility Offer system, repair the existing exact-work writer boundary.

The first implementation should:

1. prevent `organization_owner_set_company_work_responsibility_api_v1` from directly establishing a new optional responsibility merely from owner selection;
2. preserve release of an existing allocation only through a separately truthful release path, not by overloading assignment;
3. permit immediate self-adoption where the authenticated receiver is the selected membership and the command constitutes explicit uptake;
4. stop `create_communication_derived_work_self_api_v1` from assigning another member merely because the creator has Endpoint `handoff`;
5. allow Communication-derived Work to be created unassigned when another Person is proposed but no lawful receiver uptake exists;
6. preserve any existing domain-local relation-constituted writers only when they can state their explicit establishment rule/provenance;
7. make the generic internal writer require an explicit establishment-basis envelope for every newly active responsible allocation;
8. fail closed on unknown/ambiguous basis rather than defaulting to `assigned_by_owner`;
9. leave historical existing allocations untouched;
10. keep present execution warrant separate.

## 12. Migration sequencing warning

The generic internal writer has many current domain callers.

Do **not** change its signature first and break every domain.

Sequence should be:

1. inventory every current writer/caller;
2. classify each caller as self-uptake, relation-constituted, reconstructed/adjudicated, domain-local accepted handoff, or compatibility;
3. add a versioned responsibility-establishment seam/basis;
4. migrate truthful callers;
5. fail/retire compatibility writers that cannot provide a basis;
6. only then retire the old unqualified internal writer.

## 13. Management adjudication is a different authority

`organization_management_adjudicate_company_work_api_v1` may record an institutional management adjudication such as completed/not relevant/new data.

That operation is not equivalent to:

```text
manager performed the Work
```

nor:

```text
manager became responsible
```

The function already records separate management-adjudication evidence and may therefore remain a distinct audit target.

Do not use the responsibility-establishment repair to erase legitimate institutional adjudication authority.

## 14. Acceptance conditions for the establishment repair

A future production-schema clone must prove:

1. owner selection alone cannot create a new optional responsible allocation for another member;
2. manager/planner selection alone cannot create such responsibility;
3. Endpoint handoff authority alone cannot create another member's Communication-derived responsibility;
4. self-adoption can establish responsibility when the receiver is the actor and the Work is otherwise lawful;
5. a proven relation-constituted domain rule can establish exact Work with explicit basis;
6. reconstruction/adjudication can establish prior responsibility only with explicit provenance;
7. standing-intake cannot be claimed unless an executable qualifying agreement exists;
8. existing allocations are not rewritten;
9. durable institutional responsibility does not auto-allocate arbitrary exact Work;
10. responsibility remains independent of view/action/execution warrant;
11. all new responsibility rows expose establishment provenance;
12. ambiguous establishment fails closed.

## 15. Next executable question

The first executable repair should not begin with a universal offer table.

The immediate question is:

> **Which current writers are entitled to create active responsible allocations today, and what truthful establishment basis can each one actually prove?**

That caller-by-caller classification is the next implementation artifact.
