# Atlas Company Work Institutional Adjudication Authority v1

**Status:** architecture contract + executable qualification target  
**Date:** 2026-09-22  
**Parent laws:** `atlas-authority-dimensions-current-canon-v1`, `atlas-authority-required-reconciliation-company-work-v1`  
**First governed decision:** Company Work Result acceptance / rejection  
**Universal authority table:** none

## 1. Purpose

Production-live Reality Reconciliation can now identify an unresolved Company Work Result as:

```text
handlingMode = authority_required
resolver = company_work_result_adjudication
```

The first Decision Requirement proof can route that judgment to the exact current Organization owner compatibility membrane.

That compatibility must not become the constitutional law.

The next question is:

> Who has institutional adjudication authority over this exact Company Work Result?

This tranche establishes an explicit Company Work authority relation instead of treating a role label as the answer.

## 2. Governing law

> **Institutional adjudication authority is a distinct action authority. It must be explicitly granted for a bounded Company Work scope before a human may accept or reject institutional Result evidence.**

Therefore:

```text
owner
!= adjudicator

manager
!= adjudicator

durable responsibility
!= adjudicator

exact Work responsibility
!= adjudicator

Principal
!= adjudicator
```

Any of those relations may be evidence relevant to establishing a grant later.

None substitutes for the grant at decision time.

## 3. Owner remains grant authority, not decision authority

Current Organization ownership is retained in this tranche only as transitional **grant-establishing authority**.

An active, present-effective Organization owner may:

- establish a Company Work Result-adjudication grant;
- revoke such a grant;
- grant the authority to themselves;
- grant it to another present-effective Organization member.

Ownership does not itself satisfy the new Result-decision command.

This makes the authority movement explicit:

```text
Organization owner root governance
→ establishes bounded adjudication grant
→ grant holder may adjudicate
```

rather than:

```text
Organization owner
→ may adjudicate everything forever
```

## 4. Domain-local grant relation

The first explicit carrier is:

`atlas.company_work_adjudication_authority_grants`

It is deliberately Company Work-specific.

One domain does not justify a universal permission or decision-authority table.

Each active grant records:

- Organization;
- Organization Membership receiving authority;
- authority kind;
- scope kind;
- scope identity;
- granting Membership;
- grant basis;
- grant/revocation state;
- provenance.

V1 has one authority kind:

`result_acceptance`

## 5. Scope

V1 admits only two scopes.

### Organization scope

```text
scopeKind = organization
scopeId = Organization.id
```

The member may adjudicate manager-acceptance Results belonging to Company Work in that Organization.

### Exact Work scope

```text
scopeKind = work_item
scopeId = WorkItem.id
```

The member may adjudicate Results only for that exact Company Work item.

Exact Work scope outranks Organization scope when both exist for the same actor/Result.

V1 does not infer an Organization Unit scope from position, farm, title, responsibility, or textual resemblance.

If Organization Unit management later needs first-class adjudication scope, establish it explicitly in a later tranche with its own proof.

## 6. Grant basis

V1 admits:

- `explicit_owner_grant`;
- `organization_owner_compatibility_cutover`.

The compatibility-cutover basis exists only to preserve currently released owner behavior during migration.

It materializes the old role shortcut into an explicit authority row.

After cutover, the decision command no longer checks ownership.

A compatibility grant is therefore data/provenance debt, not a hidden runtime wildcard.

An owner may supersede a compatibility grant by explicitly granting the same scope.

## 7. Grant integrity

An active grant is lawful only when:

- recipient Membership belongs to the grant Organization;
- recipient Membership is present-effective when a new grant is established;
- granting Membership, when present, belongs to the same Organization;
- Organization scope identifies that exact Organization;
- Work scope identifies a Work item in that Organization;
- grant state and revocation timestamp agree.

Core grant identity is immutable after creation.

Revocation does not rewrite the original grant basis.

## 8. Authority resolver

The canonical read is:

`atlas.company_work_result_adjudication_authority_v1(execution_result_id, membership_id)`

It answers only:

> Does this exact Membership currently hold explicit Result-adjudication authority for this exact Result, and which grant proves it?

It does not:

- decide the Result;
- create a grant;
- infer authority from a role;
- infer authority from Responsibility;
- infer authority from Work Allocation;
- infer authority from Principal status;
- create Work;
- create a queue item.

The Result must already belong to an active `manager_acceptance` result contract.

## 9. New decision command

The governing browser mutation becomes:

`atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)`

The command:

1. resolves the signed-in actor's present-effective Organization Membership;
2. calls the exact adjudication-authority resolver;
3. fails closed without an active matching grant;
4. preserves the worker Result;
5. records Result Acceptance with the exact authority grant in evidence;
6. preserves current accepted/rejected Company Work consequences;
7. lets the existing Transition / Continuation / Reconciliation chain determine what follows.

The command never checks `role='owner'` as decision authority.

## 10. Old owner command becomes a compatibility wrapper

`atlas.organization_owner_decide_company_work_result_api_v1(...)` remains temporarily callable to avoid a breaking RPC removal.

It may verify that the caller is an Organization owner, but it must terminate at the new grant-governed decision command.

Therefore even the compatibility wrapper cannot adjudicate without an explicit grant.

Current production owners receive explicit Organization-scope cutover grants during migration so current live behavior remains available.

A future owner receives no adjudication authority merely from becoming owner; they may explicitly grant it through the grant-establishment operation.

## 11. Decision Requirement cutover

The production-live Decision Requirement must stop advertising:

`transitional_organization_owner_compatibility`

and instead advertise:

`explicit_company_work_adjudication_grant`

Its command contract becomes the new generic decision command.

The self detail and current-user list must use the exact authority resolver.

They must not maintain an independent owner/manager heuristic.

## 12. Durable responsibility remains separate

Current Organization Responsibilities such as:

- Production stewardship;
- Harvest execution;
- Grounds readiness;
- Venue preparation

do not establish Result-adjudication authority.

A future rule may explicitly say that a particular institutional Responsibility establishes or requires a particular adjudication grant.

Until such a rule exists:

```text
responsibility carrier
!= Result adjudicator
```

## 13. Principal authority remains separate

`principal_authority_allocations` currently carries a different Principal-governance model and has no live allocations.

This tranche does not reuse it for institutional Company Work adjudication.

A future Principal may have authority to establish, withdraw, or escalate institutional grants through a separately proven relationship.

That is not needed for this first cutover.

## 14. Farm role compatibility is rejected

The existing broad management helper can recognize Farm owner/manager compatibility in a separate management-adjudication path.

That must not be reused here.

No Company Work Result-adjudication grant is created because a Person is:

- Farm owner;
- Farm manager;
- Farm member;
- Farm steward;
- holder of a similarly named Position.

Farm is an execution adapter, not universal institutional authority.

## 15. Browser and data boundary

The grant table is not browser-readable.

Browser operations are RPC-only.

Authenticated users may:

- ask for their own Decision Requirements where the exact grant admits them;
- execute the Result decision where the exact grant admits them;
- if they are current Organization owner, establish/revoke a bounded grant.

They may not directly enumerate or mutate raw grant rows.

## 16. Current-owner cutover

Migration v1 materializes active present-effective Organization owners into explicit Organization-scope Result-adjudication grants:

```text
grantBasisKind = organization_owner_compatibility_cutover
```

This preserves current production owner capability while removing ownership from the actual decision resolver.

No historical Result Acceptance is rewritten.

No previously rejected/accepted Result is re-adjudicated.

## 17. Qualification criteria

Production-schema clone proof must establish:

1. Organization owner without an explicit grant cannot use the new decision command;
2. Organization owner without a grant cannot see an authority-required Decision Requirement through the new grant-governed self read;
3. owner can explicitly grant Result-adjudication authority;
4. grant target must be a present-effective member of the same Organization;
5. non-owner cannot establish/revoke grants;
6. exact Work grant admits only the exact Work;
7. Organization grant admits Company Work across that Organization;
8. grant from another Organization does not apply;
9. durable Organization Responsibility does not satisfy the resolver;
10. exact Work responsibility does not satisfy the resolver;
11. Farm owner/manager role does not satisfy the resolver;
12. revoked grant no longer satisfies the resolver;
13. active grantee sees the Decision Requirement;
14. unrelated member does not;
15. active grantee may accept/reject through the new command;
16. Result Acceptance evidence names the exact authority grant;
17. after acceptance the Reconciliation Plan converges to settled;
18. the Decision Requirement disappears after convergence;
19. old owner compatibility command terminates at the new grant-governed command;
20. no generic authority table, approval queue, or Decision Requirement persistence is introduced;
21. direct browser access to the grant table is denied.

## 18. Promotion boundary

This tranche establishes explicit Company Work Result-adjudication authority.

It does not yet establish:

- universal institutional decision authority;
- Organization Unit adjudication scope;
- generic management authority;
- authority inheritance from Position;
- authority inheritance from Responsibility;
- Principal-to-institution authority delegation;
- a universal grant administration engine.

Those require separate evidence.

## 19. Resulting architecture

```text
root grant authority
→ explicit Company Work adjudication grant
→ authority resolver
→ Decision Requirement visibility
→ human judgment
→ grant-governed Company Work command
→ Result Acceptance
→ canonical consequence
→ Reconciliation
→ settled / still outstanding
```

This replaces the role wildcard at the decision membrane with an explicit institutional authority relation.
