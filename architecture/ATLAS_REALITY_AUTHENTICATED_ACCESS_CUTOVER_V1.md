# Atlas Reality Authenticated Access Cutover v1

Status: implementation architecture
Date: 2026-09-25

## Purpose

Move the authenticated Atlas identity and read-access root onto the Reality / Personal Atlas / Ledger core without pretending that a Ledger Seat is ownership or governing authority.

The canonical read chain is now:

```text
Auth credential
  → Reality Person
  → native Personal Atlas
  → active Ledger Seats
  → Ledgers
  → Ledger subject Entities
```

## Identity rule

`atlas.current_person_id_v1()` keeps its compatibility name because many established APIs call it, but its source changes completely.

It now resolves:

```text
auth.uid()
  → reality.auth_person_bindings
  → reality.entities(kind=person, identity_state=canonical)
```

It no longer reads `atlas.person_auth_credentials`.

The existing `atlas.current_principal_id_v1()` may still locate the old Principal row attached to that already-canonical Person so the Principal OS can read its existing household, Clock, portfolio, capacity, and office data. That is a compatibility lookup only. The legacy Principal does not identify the Person and does not create Ledger authority.

## Read-access membrane

`atlas.reality_access_self_api_v1()` is the canonical authenticated read membrane.

It returns:
- the signed-in canonical Reality Person;
- the native Personal Atlas;
- active Ledger Seats;
- each seated Ledger;
- each Ledger's canonical Reality subject;
- an explicit truth boundary stating that Seat participation does not establish ownership or Entity authority.

Where an admitted Reality Entity has a legacy Organization carrier, the endpoint may expose that old Organization UUID only as `legacyOperationalCompatibility.organizationId`. The meaning is routing-only compatibility for old operational projections. It is not identity, membership, ownership, or authority.

## Session cutover

`atlas.current_session_context_api_v2()` composes the canonical Reality access packet with existing farm memberships.

Farm memberships remain temporarily because Worker Day and farm execution still require their established operating scope. They are not promoted into the Reality/Ledger identity model by this tranche.

The session contract deliberately does not require `atlas.organization_memberships`.

## Principal read compatibility

`atlas.principal_self_context_api_v1()` now establishes the caller through Reality access first. Only after that may it read the existing Principal OS data carrier.

`atlas.principal_ledgers_self_api_v1()` is retained by name for compatibility, but its read semantics are changed from `principal_ledger_authorities` to active Ledger Seats.

This does not mean:
- a Seat is ownership;
- a Seat grants Entity authority;
- old root-governing authority survives under a new name.

It means only that a Person may read the Ledgers in which that Person currently participates.

## Deliberate non-cutover

This tranche does not replace owner/governing write authority.

Any surface that currently performs an ownership-only, adjudicative, destructive, or institution-governing mutation remains migration debt until Atlas has a lawful Reality-era authority relation or responsibility contract to replace the retired Organization Membership / Principal Ledger Authority semantics.

The system must not solve that gap by treating every Seat as an owner.

## Acceptance

The cutover is accepted only when:
1. current Person resolution contains no `atlas.person_auth_credentials`;
2. canonical Reality access contains no `atlas.organization_memberships` or `atlas.principal_ledger_authorities`;
3. Principal Ledger reads contain no `atlas.principal_ledger_authorities`;
4. Principal self reads contain no `atlas.principal_ledger_authorities`;
5. farm execution compatibility remains explicitly separate from canonical identity/access;
6. the existing Lex / Elm Reality, Personal Atlas, Ledger, Seat, and action identities remain unchanged.
