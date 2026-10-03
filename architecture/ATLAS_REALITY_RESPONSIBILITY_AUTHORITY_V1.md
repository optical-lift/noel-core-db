# Atlas Reality Responsibility Authority v1

Status: governing implementation architecture  
Date: 2026-09-25

## Why this layer exists

Reality identity, Ledger participation, and authority are different facts.

The authenticated read cutover established:

```text
Auth → Reality Person → Personal Atlas / Ledger Seats
```

That is sufficient to know who the person is and where the person participates. It is not sufficient to answer:

> What consequential operation may this Person lawfully carry, and inside what jurisdiction?

A Seat cannot answer that question. A role cannot answer it. Possession of credentials cannot answer it.

The governing sequence is:

```text
known condition
→ responsibility relation
→ jurisdiction
→ permitted operation set
→ execution
```

## Canonical relation

`reality.responsibility_relations` establishes one bounded responsibility carried by one canonical Person.

Each relation states:

- the carrier Person;
- the responsibility key;
- the jurisdiction;
- the exact permitted operation set;
- any narrower structured scope;
- the establishment kind and basis;
- optional source Person when a later explicit delegation has one;
- the active interval.

There is no `role`, `owner`, `principal_id`, `organization_membership_id`, or Ledger Seat authority column.

## Jurisdiction

A responsibility has exactly one jurisdiction kind.

### Entity jurisdiction

Used when responsibility is exercised for a particular Reality Entity.

Example:

```text
Lex
  carries institutional_worker_capacity_truth
  for Elm Farm
  operation: worker_day_shape.author
  scope: Elm Farm legacy farm UUID only
```

The Elm relation does not authorize the same operation for Waiting Room Farm even though both old farm rows historically sat under the same compatibility Organization.

### Domain jurisdiction

Used when the governed operation is not institution-specific.

Example:

```text
Lex
  carries reality_identity_adjudication
  in reality.identity_resolution
  operations:
    - identity_review.read
    - identity_review.adjudicate
  scope:
    - ingestion_candidate_match
    - entity_merge
```

This does not grant canonical merge execution. Adjudicating a recommendation and executing an identity merge remain separate operations.

## Ledger-local seat responsibilities

`ledger.seat_responsibilities` remains a valid Ledger-local descriptor of what a participating Seat carries inside that Ledger. It is not the canonical source of authority for institution-wide or cross-Reality mutations.

A Seat responsibility must not be promoted into broader jurisdiction merely because the Seat exists. Consequential operations outside the Ledger's own bounded internal function require an explicit `reality.responsibility_relations` envelope.

## Resolver law

`reality.resolve_responsibility_relation_v1(...)` resolves only when all of these are true:

1. the carrier is the exact canonical Person;
2. the relation is active;
3. the requested responsibility key matches;
4. the requested operation is explicitly listed;
5. the jurisdiction kind and target match;
6. the stored scope contains the required scope.

Failure of any one condition means no authority.

Nothing is inferred upward from:

- Ledger Seat participation;
- old Organization Membership;
- old Principal;
- farm role;
- employee seat;
- credentials;
- visibility;
- technical capability.

## Application projection

`atlas.current_responsibility_context_self_api_v1()` exposes the signed-in Person's current responsibility envelopes.

`atlas.current_session_context_api_v2()` carries those envelopes as `responsibilities`, alongside—but semantically separate from—farm execution compatibility.

The application may use the projection to hide or admit a surface. The database mutation must still resolve the exact responsibility again. UI admission is not the authority boundary.

## Identity adjudication cutover

The v2 identity review path is:

```text
Auth
→ Reality Person
→ reality_identity_adjudication responsibility
→ reality.identity_resolution domain
→ review-kind scope
→ queue read / adjudication
```

The old test of “is this user an Organization owner somewhere?” is not part of v2.

Reviewer provenance records the canonical Reality Person and the exact responsibility relation.

## Worker capacity cutover

The new institutional Day Shape path is:

```text
Auth
→ Reality Person
→ legacy farm compatibility lookup
→ canonical institution Entity
→ institutional_worker_capacity_truth responsibility
→ exact farm scope
→ worker_day_shape.author
→ internal Day Shape mutation
```

The mutation core no longer needs to know why the caller is authorized. The compatibility owner wrapper may continue to exist temporarily for old product surfaces, but the Reality-era Principal exception path does not use it.

## Initial adjudicated responsibilities

This migration establishes exactly two current Lex responsibilities:

1. `reality_identity_adjudication` in the Reality identity-resolution domain;
2. `institutional_worker_capacity_truth` for Elm Farm, scoped only to the Elm Farm legacy farm row.

They are recorded as `legacy_adjudicated_migration`, not as preservation of the old `owner` or Principal labels.

No generalized “Lex owns Elm” relationship is created.

## Non-implications

A responsibility relation does not imply:

- ownership;
- employment;
- membership;
- Ledger participation;
- authority over unlisted operations;
- authority over another Entity;
- authority over another domain;
- the right to delegate itself;
- destructive authority unless a destructive operation is explicitly listed.

## Acceptance

This tranche is accepted only when:

- the new relation contains no role/owner/Principal/Organization Membership dependency;
- identity v2 contains no Organization Membership or Principal authority check;
- identity adjudication cannot resolve `canonical_merge.execute`;
- Elm capacity responsibility cannot resolve for Waiting Room Farm;
- the new institutional Day Shape API contains no `is_farm_owner` or Organization Membership authority check;
- the existing owner Day Shape API remains a compatibility wrapper for still-running old surfaces;
- the application gates the two Principal mutation surfaces from explicit responsibility envelopes;
- every write re-checks responsibility in the database.
