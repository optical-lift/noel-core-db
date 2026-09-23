# Atlas Domain Exposure Evaluator v1

**Status:** candidate architecture only  
**Date:** 2026-09-23  
**Repository role:** canonical database candidate custody. No migration identity, production release, notebook mutation, or application deployment is implied.

## Purpose

Establish the first shared read-only database membrane between Person Position and notebook admission.

The evaluator answers:

> Given the authenticated Person's current governed position, which already-owned domain realities are eligible to participate in that Person's notebook, and at what exposure depth?

It does not create source truth, notebook places, source bindings, Index rows, Today placement, action authority, or execution authority.

## Governing chain

```text
canonical domain truth
→ domain-owned governed read
→ Person Position
→ Domain Exposure Evaluation
→ later notebook-admission planning
→ later reconciliation/mutation authority
```

For attention:

```text
domain truth
→ Person Position
→ Domain Exposure Evaluation
→ attention nomination only
→ later Clock / encounter arbitration
```

The evaluator never owns Today.

## V1 proof domains

### Person Life

Private Person-owned Life definitions are read only through `atlas.person_life_state_api_v1()`.

For each definition:

- active definitions remain eligible, stable, open, and listed;
- retired definitions remain owner-retrievable durable history, stable, closed, and listed under the current Index law;
- relationship kind follows existing notebook law: Goal → `progress`, Rhythm → `cadence`, Consequence → `state`;
- definition existence never creates Today placement or execution warrant.

### Connections

Connections is a permanent Principal orientation.

An active Principal context from Person Position may emit:

- stable place key `connections`;
- open carrier;
- listed Index disposition;
- governed source binding to `atlas.connected_sources_self_api_v1`;
- quiet attention nomination.

Connections existence does not establish provider authorization, synchronization, complete coverage, downstream Life truth, or domain action authority.

### Organization Ledger

Current Ledger notebook admission remains explicitly transitional.

V1 requires both:

1. current `owner` Organization Membership compatibility visible through Person Position; and
2. a matching root-governing Ledger context already returned by Person Position.

Only then may the evaluator emit stable/open/listed Ledger exposure.

Ordinary membership is explicitly ineligible. Owner compatibility without a matching Ledger context is unresolved. A root-governing Ledger context without current owner compatibility is still not exposed by this transitional contract.

Future cutover to exact Principal Ledger authority must preserve the same durable key `ledger:<organizationId>`.

## Common evaluation envelope

Every emitted item uses `domain_exposure_evaluation_v1` and preserves these independent dimensions:

```text
encounter eligibility
!= durable place disposition
!= desired carrier state
!= Index disposition
!= attention nomination
!= source binding
!= action authority
```

The evaluator returns:

- `contractKey`
- `personRef`
- `contextRef`
- `subjectRef`
- `encounter`
- `place`
- `index`
- `attentionNomination`
- optional `sourceBinding`
- `stateQuality`
- `disclosure`
- `operations`
- `prohibitedInferences`

## Person Position dependency

The evaluator must consume `atlas.person_position_self_api_v1()`.

It may not reconstruct Person, Principal, Household, Organization Membership, durable Responsibility, Ledger authority, or Connected Source orientation from arbitrary tables.

If Person Position is unavailable, the evaluator returns an explicit dependency state and no exposure items.

If Person Position does not resolve a canonical Person, no exposure item may be synthesized.

## Table-blind shared evaluator rule

The V1 shared evaluator intentionally performs no direct table reads.

It may call only governed self membranes and reason over their returned contracts.

That preserves:

```text
shared evaluation != second truth graph
shared evaluation != universal ACL table
shared evaluation != role matrix
```

## No persistence

V1 adds no exposure table and no generic permission store.

The function contains no durable `INSERT`, `UPDATE`, or `DELETE` path.

It does not call notebook ensure/sync/bind functions.

Later notebook-admission reconciliation remains a separate authority.

## Security boundary

`atlas.domain_exposure_evaluations_self_api_v1()` is self-only.

- no Person id parameter;
- requires authenticated `auth.uid()`;
- resolves identity through Person Position;
- exposes Person Life only through its existing signed-in self read;
- grants no cross-Person or institutional disclosure of private Life truth.

## Required proofs

Clone validation must prove at least:

1. credential without canonical Person emits no exposure;
2. active and retired Person Life definitions use the same contract while preserving open/closed carrier distinction;
3. Connections exists for an active Principal without implying provider connection;
4. owner membership plus matching root Ledger context emits Ledger exposure;
5. ordinary membership does not emit Ledger exposure even if a root Ledger context still exists;
6. no item grants Today placement or action authority;
7. the evaluator performs no durable mutation;
8. the evaluator contains no direct domain-table reconstruction.

## Dependency / promotion boundary

The Person Position candidate `20260923021153_atlas_person_position_self_projection_v1` is clone-green but, at the time this source candidate was written, remains unreleased.

Therefore this evaluator source may be reviewed and merged as candidate source, but production-schema clone validation of the generated evaluator package must wait until Person Position is canonical in the receiving production schema.

Do not solve that dependency by copying Person Position logic into this evaluator.

Passing future clone validation will still not authorize production release.
