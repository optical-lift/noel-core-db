# Atlas Authority-Required Reconciliation — Company Work Proof v1

**Status:** production-live Company Work authority-required reconciliation proof  
**Date:** 2026-09-22  
**Parent law:** `architecture/atlas-reality-reconciliation-protocol-v1.md`  
**Authority law:** `architecture/atlas-authority-dimensions-current-canon-v1.md`  
**First proof domain:** Company Work result acceptance  
**Universal decision engine:** none

## 1. Purpose

Reality Reconciliation v1 can now say truthfully:

```text
Work Result reported
→ acceptance unresolved
→ handlingMode = authority_required
```

That is still not enough to reach a human safely.

The missing question is:

> When a Reconciliation Plan says human authority is required, how may Atlas expose the exact decision to an actually authorized human without turning the condition into Work, a queue, a permission grant, or an automatic decision?

This tranche proves that bridge in one domain only: Company Work result acceptance.

## 2. Core law

> **An authority-required reconciliation may become a human Decision Requirement only when Atlas can name the exact unresolved canonical source, the exact owning-domain decision, the exact currently released authority membrane, and the post-decision convergence test.**

A Decision Requirement is a projection.

It is not:

- Company Work;
- a task;
- a queue row;
- an authority grant;
- a responsibility allocation;
- a Principal Clock candidate;
- a new truth store;
- a generic approval engine.

The first artery is:

```text
Company Work Execution Result
→ Reality Reconciliation Plan
→ authority_required
→ Company Work Decision Requirement
→ exact current actor-authority check
→ human Accept / Reject
→ existing owning-domain command
→ Work Result Acceptance
→ canonical Company Work consequence
→ Transition Receipt / Continuation / Reconciliation
→ settled
```

## 3. Why Company Work is the first proof

The released Reconciliation contract already classifies an unaccepted Company Work Result as:

```text
resolver = company_work_result_adjudication
handlingMode = authority_required
automation.eligible = false
```

Company Work also already has a released mutation membrane for the exact decision:

`atlas.organization_owner_decide_company_work_result_api_v1(uuid,text,text)`

That command accepts `accepted` or `rejected`, preserves the worker report, and changes institutional truth only through the owning Company Work domain.

Therefore this tranche does not need to invent a mutation command.

It needs to make the unresolved decision legible and routable without changing who may decide it.

## 4. Current authority is compatibility, not constitutional law

The existing result-acceptance command is currently restricted to an active Organization owner.

That is a real released authority membrane, but it is not promoted here into the universal meaning of management or adjudication authority.

The Decision Requirement must therefore expose the current basis honestly:

```text
authorityBasis = transitional_organization_owner_compatibility
```

This tranche must not claim:

```text
owner = manager = adjudicator
```

or:

```text
farm role manager
→ may accept every Company Work Result
```

The broader helper `atlas.can_adjudicate_company_work_v1(uuid)` currently includes farm-owner/manager compatibility for a different management-adjudication path.

It is **not** the authority resolver for this result-acceptance proof because the exact result-acceptance command does not authorize that same population.

Routing must match the command that can actually produce the consequence.

## 5. Management adjudication remains a different operation

`atlas.organization_management_adjudicate_company_work_api_v1(...)` can establish separate management adjudication such as:

- completed;
- not relevant;
- new data.

It is not a substitute for accepting or rejecting an already-reported worker Result.

This tranche must not make the false movement:

```text
management may adjudicate Work generally
→ management has accepted this existing Result
```

The Result Acceptance remains its own canonical consequence.

## 6. Decision Requirement shape

The first domain-local contract is:

`company_work_result_decision_requirement_v1`

Minimum shape:

```json
{
  "contractVersion": "company_work_result_decision_requirement_v1",
  "state": "decision_required",
  "source": {
    "domain": "company_work",
    "kind": "work_execution_result",
    "ref": "..."
  },
  "work": {
    "workItemId": "...",
    "organizationId": "...",
    "title": "..."
  },
  "reportedResult": {
    "resultKind": "completed",
    "reportedAt": "..."
  },
  "decision": {
    "kind": "company_work_result_acceptance",
    "options": ["accepted", "rejected"],
    "command": {
      "key": "organization_owner_decide_company_work_result",
      "signature": "atlas.organization_owner_decide_company_work_result_api_v1(uuid,text,text)"
    }
  },
  "authorityRequirement": {
    "dimension": "institutional_adjudication_authority",
    "currentBasis": "transitional_organization_owner_compatibility"
  },
  "truthBoundary": {
    "readOnly": true,
    "doesNotDecide": true,
    "doesNotGrantAuthority": true,
    "doesNotCreateWork": true,
    "doesNotCreateQueueState": true
  }
}
```

The internal projection may describe the requirement.

It may not answer whether an arbitrary browser actor is authorized.

## 7. Actor-safe self membrane

A browser-facing self reader may expose the Decision Requirement only when the signed-in actor satisfies the exact current authority prerequisites of the existing result-acceptance command.

For v1 that means:

- authenticated user;
- active Organization owner membership for the Work's Organization;
- `atlas.is_organization_owner(organization_id)` is true.

The self membrane must not use a broader management helper merely because it sounds semantically adjacent.

If the actor is not eligible, the detail reader fails closed rather than returning decision evidence for an arbitrary Result ID.

## 8. Minimal disclosure

Action authority does not automatically imply unrestricted knowledge authority.

The first browser Decision Requirement therefore exposes only the minimum context needed to identify the decision:

- Work identity;
- Organization identity;
- Work title;
- Result identity;
- result kind;
- reported time;
- exact decision options;
- exact command contract;
- current authority basis.

It does **not** expose in v1:

- arbitrary Result payload;
- worker-authored narrative;
- unrelated Work evidence;
- broader employee/person details;
- all Result history.

A future deep-inspection surface must pass its own Knowledge / Exposure authority test.

## 9. Current-user Decision Requirements are a projection, not a queue

Atlas may provide a self-scoped list of currently unresolved Company Work Decision Requirements.

That list is derived at read time from canonical state:

```text
current actor's exact released authority
+ unaccepted manager-acceptance Work Results
+ current Reconciliation Plan says authority_required
→ visible Decision Requirement
```

No `decision_requirements`, `approval_queue`, `reconciliation_queue`, or similar persistence is created.

Once canonical reality reconciles, the item disappears from the projection because the Reconciliation Plan no longer requires a decision.

## 10. Static command binding

The Decision Requirement may name the exact current command as descriptive contract metadata.

It must never execute a function by a resolver key or string name.

The human action path remains a normal direct call to:

`atlas.organization_owner_decide_company_work_result_api_v1(...)`

No dynamic dispatch is introduced.

## 11. Convergence is the completion test

The human decision is not complete merely because the command returned success.

The proof is:

```text
before:
Reconciliation Plan = authority_required

human decision:
existing owning-domain command

after:
Reconciliation Plan = settled
```

If the post-decision plan instead reports an invariant repair or other outstanding continuation, Atlas must preserve that state rather than falsely declaring the whole matter settled.

## 12. Relationship to Principal / Clock

This tranche does not decide whether a Decision Requirement enters the Principal Clock.

It proves only that:

- the unresolved decision can be represented;
- the exact current actor authority can be checked;
- the decision can be executed through the owning command;
- convergence can be verified.

Later Responsibility / Principal routing may decide who gets the floor and when.

Do not make every `authority_required` reconciliation an interrupt merely because it exists.

## 13. No universal Decision Requirement engine yet

One domain proves necessity, not universality.

Do not introduce:

- a universal decision table;
- a universal approval state machine;
- a generic command router;
- a generic authority resolver;
- generic decision history;
- a cross-domain Decision Requirement normalizer.

After a second genuinely unrelated `authority_required` domain proves the same structure, compare the two and promote only what is actually shared.

## 14. First executable tranche

Introduce internal/read-only:

- `atlas.company_work_result_decision_requirement_v1(uuid)`.

Introduce actor-safe browser reads:

- `atlas.company_work_result_decision_requirement_self_api_v1(uuid)`;
- `atlas.company_work_decision_requirements_self_api_v1(integer)`.

No new mutation command is introduced.

The existing result-acceptance command remains the only browser mutation used by this proof.

## 15. Qualification criteria

Production-schema clone proof must establish:

1. an unresolved manager-acceptance Result becomes exactly one `decision_required` projection;
2. the projection is derived from the released Reconciliation Plan, not from a parallel acceptance heuristic;
3. the requirement names the exact existing result-acceptance command;
4. the requirement labels current owner authority as transitional compatibility;
5. internal requirement projection does not mutate Result Acceptance;
6. browser detail is available to an exact current Organization owner;
7. a non-owner cannot read the Decision Requirement detail;
8. a non-owner receives no item in the self list;
9. the self list is derived, with no queue/persistence table;
10. browser reads expose no arbitrary Result payload;
11. browser reads do not call the mutation command;
12. the non-owner cannot invoke the existing decision command;
13. the owner can invoke the existing decision command;
14. after owner acceptance, the same Reconciliation Plan is settled;
15. the Decision Requirement disappears after convergence;
16. no generic decision/approval/reconciliation storage is introduced;
17. no dynamic command dispatch is introduced;
18. no browser execute grant is added to the internal Reconciliation Plan or internal Decision Requirement reader.

## 16. Promotion boundary

This first proof does not authorize broader management routing.

Before Atlas routes Company Work result decisions to non-owner managers or durable responsibility carriers, it must establish a current-canon authority seam that answers:

> Who has institutional adjudication authority over this exact Company Work Result?

That future repair may reuse durable Responsibility, Scope, explicit management authority, Principal delegation, or another proved relationship.

It may not infer authority merely from a farm adapter role.

## 17. Resulting architecture

```text
Reality changes
→ Reconciliation says authority_required
→ domain-local Decision Requirement
→ exact current actor authority
→ human judgment
→ owning-domain command
→ canonical consequence
→ Reconciliation re-read
→ settled or explicitly still outstanding
```

This closes the first human-judgment reconciliation loop without creating a generic workflow engine.


## 18. Production receipt — 2026-09-22

The first authority-required reconciliation proof crossed production on September 22, 2026.

Canonical lineage:

- architecture/candidate PR #1157 → merge `60b08eadcad4b803e733d43a603feb43cedef439`;
- governed generation request #1158;
- generated migration `20260922163955_atlas_authority_required_reconciliation_company_work_v1.sql`;
- generated package SHA `d35afa8cc2de96ea615486329c105d686c7aa63e`;
- generated package PR #1159 → merge `3a2b8a022c234ea31a2b18509fdf900929a7d9cb`;
- Production Schema Clone Validation request #1160;
- Production Schema Clone Validation run `35755771236` → PASS;
- governed production release request #1161;
- Production Database Release run `35757926840` → PASS;
- production migration ledger contains version `20260922163955`.

Production now exposes:

- internal-only `atlas.company_work_result_decision_requirement_v1(uuid)`;
- authenticated self read `atlas.company_work_result_decision_requirement_self_api_v1(uuid)`;
- authenticated derived list `atlas.company_work_decision_requirements_self_api_v1(integer)`.

Direct production verification confirms:

- `authenticated` cannot execute the internal Decision Requirement reader;
- `authenticated` can execute both actor-safe self projections;
- `anon` can execute neither self projection;
- no new Company Work mutation command was introduced by this tranche;
- no generic persisted Decision Requirement / approval / reconciliation queue was introduced;
- the current actor-authority basis remains explicitly labeled `transitional_organization_owner_compatibility`, rather than being promoted into universal management authority.

The production-schema clone proved the full closed loop:

```text
unaccepted manager-acceptance Result
→ Reconciliation = authority_required
→ Decision Requirement
→ non-owner denied
→ exact current owner admitted
→ existing result-acceptance command
→ canonical Company Work completion/consequence
→ Reconciliation re-read
→ settled
→ Decision Requirement disappears
```

This establishes the first lawful human-judgment reconciliation artery.

It still does not justify a universal Decision Requirement engine, generic approval queue, generic authority resolver, automatic human judgment, or manager authority inferred from a Farm adapter role.


## 19. Authority cutover update — 2026-09-22

The authority basis recorded in the original production receipt has now been superseded.

Migration `20260922175802_atlas_company_work_institutional_adjudication_authority_v1` replaced runtime owner-only Result adjudication with explicit Company Work adjudication grants.

Current movement:

```text
Decision Requirement
→ explicit_company_work_adjudication_grant
→ company_work_result_adjudication_authority_v1
→ organization_decide_company_work_result_self_api_v1
```

Existing production owner capability was preserved by materializing an explicit `organization_owner_compatibility_cutover` grant.

That grant is data/provenance compatibility, not owner role inference. If revoked, ownership alone does not recreate Result-adjudication authority.

Therefore the earlier `transitional_organization_owner_compatibility` decision basis is historical for the first proof and is no longer the current production decision membrane.
