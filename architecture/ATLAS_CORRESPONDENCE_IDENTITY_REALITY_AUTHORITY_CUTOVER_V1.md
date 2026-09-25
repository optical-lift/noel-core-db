# Atlas Correspondence Identity Reality Authority Cutover v1

Status: governing implementation architecture  
Date: 2026-09-25

## Purpose

Correspondence identity is a custody and presentation concern: which human or institution a communication endpoint speaks as.

That authority must not arise from a generic Organization role.

The canonical chains are now:

```text
personal endpoint
Auth
→ Reality Person
→ native Personal Atlas
→ matching personal communication endpoint
→ correspondence identity administration
```

and:

```text
institutional endpoint
Auth
→ Reality Person
→ explicit Reality responsibility
→ canonical institution jurisdiction
→ exact communication endpoint scope
→ correspondence identity administration
```

## Elm Farm cutover

Elm Farm has one active institutional communication endpoint:

- email endpoint: `hello@elmfarm.co`;
- legacy endpoint UUID: `7617a7b1-8713-4520-923f-51a15c6b2d7f`;
- canonical Reality Entity: `elm-farm`;
- existing correspondence identity: `Elm`.

Lex receives the bounded responsibility:

- key: `institutional_correspondence_administration`;
- jurisdiction: Elm Farm Reality Entity;
- operations:
  - `correspondence_identity.admin`;
  - `correspondence_identity.read`;
- scope: the exact Elm communication endpoint UUID.

This responsibility does not grant send, claim, handoff, close, Company Work, financial, or general institutional authority.

## Legacy endpoint grant

The existing endpoint membership grant remains temporarily because the communication transport tables still address legacy Organization Membership carriers.

It is now interpreted only as a **compatibility carrier constraint**.

It does not establish authority.

The new correspondence membrane deliberately ignores the membership's generic role. A matching endpoint grant must exist, but the Reality responsibility is what authorizes the institutional operation.

Other communication operations remain outside this tranche and retain their existing authorization until separately cut over.

## Shared authorization membrane

The existing public correspondence RPC names are preserved.

Their shared authorization helpers now classify custody:

- personal correspondence identity → Reality Person + Personal Atlas;
- institutional correspondence identity → Reality responsibility + exact endpoint scope.

This automatically cuts:

- create correspondence identity for endpoint;
- bind endpoint to correspondence identity;
- set monogram/icon mark;
- prepare logo upload;
- commit logo upload;
- read/storage authorization through the correspondence identity helpers.

## Compatibility mapping

`atlas.reality_entity_for_legacy_organization_internal_v1(uuid)` resolves a legacy Organization UUID through `compatibility.legacy_bindings` to its canonical Reality Entity.

This is a routing bridge only. The legacy Organization row does not become canonical identity again.

## Acceptance

Accepted only when:

1. Elm correspondence administration resolves through the new responsibility;
2. the responsibility is limited to the Elm Reality Entity and exact Elm endpoint;
3. the shared manage/read helpers contain no Organization Membership lookup or owner-role check;
4. create/bind correspondence APIs contain no Organization Membership authority lookup;
5. personal correspondence identity still resolves through Reality Person + Personal Atlas;
6. an actual correspondence mark mutation succeeds in a rollback proof;
7. the mark mutation does not persist after rollback;
8. send/claim/handoff/close authority is not broadened by this migration.
