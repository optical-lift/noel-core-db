# Atlas Reality / Ledger Legacy Cutover Map v1

Status: migration governance
Date: 2026-09-24

This document prevents the pre-Reality identity model from leaking into new Atlas work while production remains partially dependent on it.

## Hard rule

New architecture must not use any of the following as identity or authority truth:

- `atlas.organizations`
- `atlas.principals`
- `atlas.organization_memberships`
- `atlas.principal_ledger_authorities`

The new schemas `reality`, `personal`, `ledger`, and `compatibility` contain no foreign keys to those structures.

Any legacy read needed during migration must cross through an explicit one-way compatibility adapter or `compatibility.legacy_bindings`.

## Table disposition

| Legacy surface | Disposition | New meaning |
| --- | --- | --- |
| `local_intel.entities` | admit / reconcile / split / hold | Evidence-backed candidates for `reality.entities`; never blindly copied |
| `local_intel.entity_relationships` | migrate selectively | Real-world relationships in `reality.entity_relationships` after identity admission |
| legacy entity contact evidence | migrate selectively | `reality.contact_routes` with source/evidence preserved |
| `atlas.person_auth_credentials` | migrate after Person admission | `reality.auth_person_bindings` |
| `atlas.organizations` | retire as identity authority | No replacement Organization identity table |
| `atlas.principals` | retire | Auth binds to canonical Person directly |
| `atlas.principal_ledger_authorities` | retire | No Principal-governs-Ledger layer |
| `atlas.organization_memberships` | decompose, never 1:1 copy | Real-world connection, Ledger Seat, and responsibility are separate truths |
| `atlas.ledgers` | migrate deliberately | New `ledger.ledgers` whose subject is a `reality.entities` row |
| `atlas.ledger_organization_participations` | retire | Ledger subject is direct; Organization intermediary disappears |
| `atlas.ledger_relationships` | adjudicate before migration | May become `ledger.connections` only when it represents summary-observation composition |
| Organization positions / responsibilities | migrate by Ledger context | `ledger.seat_responsibilities` and later Ledger operating structures |
| Organization work / events | migrate by Ledger custody | `ledger.actions` / `ledger.observations` where semantically appropriate |
| claimant identity machinery | preserve evidence, reinterpret | `reality.entity_claims` and `reality.entity_claim_challenges` |
| Smart Contacts / Shared Intelligence evidence | preserve acquisition function | Feeds Reality; does not create a second identity plane |

## Membership decomposition rule

A legacy Organization Membership must never automatically become a Seat.

A historical membership row may have been carrying several unrelated ideas at once:

1. which human credential was signed in;
2. which Person the credential belonged to;
3. whether the Person had a real-world relationship to an institution;
4. whether the Person could see or act in software;
5. an owner/admin/member label;
6. work responsibility;
7. billing or invitation history.

During migration, each fact must be adjudicated independently.

Possible outcomes include:

```text
legacy membership
  ├── Auth credential → canonical Person binding
  ├── real-world employment/ownership/etc. → Reality relationship
  ├── participation in a specific Ledger → Seat
  ├── actual work scope → Seat responsibility
  └── obsolete compatibility role → retired
```

No "owner" role migrates into generalized Atlas authority.

## Ledger migration rule

An old `atlas.ledgers` row does not automatically become a new Ledger.

Before admission, Atlas must establish:

1. the canonical subject Entity;
2. the operational reality the Ledger represents;
3. whether it is genuinely separate from sibling Ledgers;
4. its migration / practitioner-onboarding basis;
5. which historic actions belong in it;
6. which people should have Seats;
7. which connections expose summaries to other Ledgers.

A new Ledger points directly to `reality.entities.id`.

## Shared Intelligence admission rule

Existing Shared Intelligence UUIDs should be preserved when the existing record is already the correct canonical real-world identity.

Admission states:

- **admit as-is** — identity is already correct; preserve UUID;
- **reconcile** — identity is real but attributes/type/boundary need correction;
- **split** — one legacy record conflates multiple real things;
- **hold** — insufficient evidence to establish canonical identity.

Example:

The current Shared Intelligence "Elm Farm" row is typed as `place` and carries farm/business/venue concepts together. It is therefore not eligible for blind admission as the canonical Elm institutional Entity.

## Product freeze

Until a product surface is explicitly cut over:

- existing production behavior may continue using legacy compatibility code;
- no new product feature may introduce additional Principal / Organization Membership / Principal Ledger Authority dependency;
- no new durable object should be owned merely by `atlas.organizations`;
- no new Ledger should be created through legacy Principal authority;
- no Smart Contacts saved search should be persisted for an institution merely because an old Organization row exists.

## First cutover

The first real migration tranche is Lex + Elm.

Acceptance target:

```text
Lex [Reality Person]
  ↓ Auth binding
Personal Atlas

Elm Farm [Reality Entity]
  ├── Flower Ledger
  └── Venue Ledger

Lex
  ├── Seat → Flower Ledger
  └── Seat → Venue Ledger
```

That graph must function without using legacy Principal, Organization Membership, Principal Ledger Authority, or Organization-as-identity truth.

Feast Guild should not be migrated merely to prove composition. It can remain unadmitted until its real Entity boundary and practitioner Ledger onboarding are deliberately established.


## First cutover result

Lex + Elm is now the first completed real migration.

Adjudicated mappings:

- `atlas.people / Lex` → same UUID in `reality.entities`;
- `atlas.person_auth_credentials / Lex` → same credential UUID in `reality.auth_person_bindings`;
- `local_intel.entities / Elm Farm` → same UUID in `reality.entities`, reconciled from legacy `place` to canonical business/entity;
- legacy `atlas.organizations / Elm Farm` → maps to that same Reality Entity, not a second identity;
- legacy Elm Farm Ledger → same UUID as `ledger.ledgers / elm-farm:flower`;
- legacy Elm Venue Ledger → same UUID as `ledger.ledgers / elm-farm:venue`;
- Lex legacy Organization Membership → split into two Ledger Seats, with the legacy `owner` role explicitly not preserved;
- Lex legacy Principal → retired;
- both Elm Principal Ledger Authority rows → retired;
- both Elm Ledger→Organization participation rows → retired;
- the legacy Elm Ledger sibling relation → retired rather than converted to a Ledger connection;
- all 23 legacy Elm Farm Ledger entries → same UUIDs in `ledger.actions`.

This cutover establishes the migration pattern: preserve valid identity/action UUIDs, decompose conflated semantics, and retire authority carriers rather than translating them into equivalent-looking new authority structures.
