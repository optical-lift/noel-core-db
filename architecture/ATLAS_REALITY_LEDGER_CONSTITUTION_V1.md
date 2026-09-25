# Atlas Reality / Ledger Constitution v1

Status: foundational architecture
Date: 2026-09-24

## Constitutional reset

Atlas represents reality. Atlas does not create reality merely because a Person signs up or an institution begins using Atlas.

The canonical subject is the real-world Entity.

A Person, business, institution, household, place, farm, church, venue, or other real thing exists independently of Atlas. Atlas may know an Entity before that Entity ever signs up.

There is one canonical identity plane.

Legacy `atlas.organizations`, `atlas.principals`, `atlas.organization_memberships`, and `atlas.principal_ledger_authorities` are transitional compatibility structures. They are not permitted as dependencies of the Reality / Ledger core and must not be used as foundations for new architecture.

## 1. Reality

`reality.entities` is the new canonical identity root.

An Entity may be known only through public evidence, may later be claimed by a Person, may later participate in Atlas operationally, and may later retire. These state changes do not create replacement identities.

Example:

```text
Happy-Bee Flower Co.
  exists in Reality
  ↓
Atlas already knows email / phone / postal routes
  ↓
a Person begins Atlas signup
  ↓
Atlas notices the Person is connected to Happy-Bee
  ↓
the Person may claim standing around the existing Happy-Bee Entity
```

Atlas must never create "Happy-Bee #2" simply because someone begins signup.

## 2. Auth is a credential binding, not an identity ontology

A Supabase Auth account binds directly to a canonical Person Entity through `reality.auth_person_bindings`.

```text
auth.users
  ↓ credential binding
reality.entities(kind=person)
```

No Principal intermediary is required by the new core.

A Person may have multiple credentials over time. Authentication proves which Person is present; it does not itself establish real-world ownership, employment, representation, or Ledger participation.

## 3. Personal Atlas is native

A human Person with an active Auth binding has a native Personal Atlas.

`personal.atlases` is not a Ledger.

Personal Atlas requires no practitioner onboarding. It is the native personal action / observation space attached to a human Atlas account.

Terminology rule:

> Never call the native human space a Ledger.

"Ledger" is reserved for the practitioner-onboarded institutional / business side of Atlas.

## 4. Ledger

A Ledger is:

> an Entity expressing its actions so those actions can be observed.

A Ledger is not an Entity.

A Ledger does not own its subject Entity.

A human with access to a Ledger does not thereby own or govern the subject Entity.

Every Ledger has exactly one canonical subject Entity.

One Entity may have multiple Ledgers when it expresses genuinely separate operational realities.

Example:

```text
Elm Farm [Entity]
  ├── Flower Ledger
  └── Venue Ledger
```

The Ledgers remain separate action worlds even though the same Entity expresses both.

## 5. Ledger activation requires practitioner onboarding

Business / institutional Ledger activation is deliberate.

A Ledger may not be minted merely because:
- an Entity exists;
- a Person claims the Entity;
- an Auth user exists;
- a Person pays for Atlas;
- an old Organization row exists.

Every genuinely new Ledger must arise from a `ledger.onboarding_cases` record that reaches `ready_to_activate` with a practitioner assigned.

A Ledger that already existed before the Reality/Ledger constitutional cutover may enter through `case_kind=legacy_adjudicated_migration` only when its historical identity and operating boundary have been explicitly adjudicated. This migration path prevents Atlas from inventing a practitioner who did not historically onboard that Ledger; it is not available for creating new Ledgers.

A verified Entity claim may initiate or support onboarding, but verification does not itself create a Ledger.

## 6. Claiming an existing Entity

Any Person may express interest in activating Atlas around an already-known Entity.

The initial ceremony is possession-based against a contact route Atlas already knows for that Entity.

Possible challenge routes include:
- email;
- SMS / phone;
- physical mail.

The sequence is:

```text
Person
  ↓ says "this is me / I represent this Entity"
existing canonical Entity
  ↓
Atlas challenges an already-known route on that Entity
  ↓
successful possession proof
  ↓
verified claim standing
  ↓
practitioner Ledger onboarding may begin
```

A verified claim establishes only the verified claim standing that its evidence supports.

It does not establish:
- ownership;
- employment;
- legal representation;
- canonical identity of the Entity;
- a Ledger Seat;
- a Ledger;
- access to another Ledger.

Real-world facts such as `Person owns Business` remain Entity-to-Entity relationships in Reality and require their own evidence.

## 7. Connections are reality; Seats are participation

A real-world relationship and a Ledger Seat are different things.

`reality.entity_relationships` records real-world facts such as:
- owns;
- works_at;
- supplies;
- buys_from;
- advises;
- married_to;
- parent_of;
- located_at.

These relationships do not grant Ledger access.

A `ledger.seats` row means only:

> this Person participates in this Ledger.

A Seat does not by itself state:
- ownership;
- authority over the Entity;
- who paid for the Seat;
- why the Person is connected to the Entity.

Those are separate facts.

## 8. Responsibility is contextual to a Seat

A Seat may carry one or more responsibilities inside the Ledger.

`ledger.seat_responsibilities` describes what that Person is responsible for in that action world.

Example:

```text
Katie [Person]
  ↓ Seat
Elm Flower Ledger
  ↓ Responsibility
Wholesale relationships
```

Responsibility should be modeled as the work / scope itself rather than a generic role hierarchy masquerading as reality.

## 9. Ledger actions and observations

`ledger.actions` records actions expressed through a Ledger.

`ledger.observations` records observations derived from actions or otherwise established inside that Ledger.

`ledger.summaries` produces higher-order state from the intricate daily reality.

A Ledger therefore behaves like:

```text
Entity
  ↓ expresses actions through
Ledger
  ↓
Actions
  ↓
Observations
  ↓
Summaries
```

## 10. Ledger composition is observational, not ownership or permission inheritance

Ledgers may be chained without a fixed depth limit.

A Ledger connection means one Ledger has a reason to observe summaries exposed by another Ledger.

Example:

```text
Elm Flower Ledger
  ↓ publishes summary exposure
Feast Guild Ledger

Farm #2 Ledger
  ↓ publishes summary exposure
Feast Guild Ledger
```

Feast Guild receives the bird's-eye output necessary to understand the enterprise without inheriting Elm's raw operational world.

A Ledger connection does not imply:
- ownership of the source Ledger;
- raw database access;
- permission inheritance;
- Seat inheritance;
- access to every action;
- access to every Person seated in the source Ledger.

The source Ledger publishes a governed summary. The observing Ledger consumes that summary.

This can compose recursively:

```text
Greenhouse Ledger
  ↓ summary
Farm Ledger
  ↓ summary
Regional Ledger
  ↓ summary
Enterprise Ledger
```

There is no artificial nesting-depth limit. Evaluation code must nevertheless be cycle-safe.

## 11. Seats and Ledger connections solve different problems

If Katie has a Seat in Elm Farm and Feast Guild, Katie may personally participate in both.

That does not make Feast Guild able to observe Elm Farm.

For Feast Guild itself to receive Elm's bird's-eye state, there must be a Ledger connection and published exposure.

Conversely, Katie may have a Seat in Feast Guild and no Seat in Farm #2 while still seeing Farm #2's published high-level summary inside Feast Guild.

Rule:

> Seats determine where a Person participates. Ledger connections determine what one Ledger may observe about another Ledger.

## 12. Billing is not authority

Who pays for a Seat, Ledger, or connected service must never become identity or authority truth.

Payment may fund participation. It does not prove:
- ownership of the Entity;
- representation of the Entity;
- employment;
- right to mutate Reality;
- access outside the purchased Seat / service.

Billing will be modeled separately.

## 13. Shared Intelligence becomes an acquisition layer, not the identity authority

Existing `local_intel` research has valuable evidence, identity-resolution, source, and contact-route material.

It is not automatically the new Reality core.

Existing external entities must be admitted through an identity migration discipline:

- admit as-is;
- reconcile;
- split;
- hold.

Where an existing Shared Intelligence Entity is already the correct canonical real-world subject, Reality should preserve that UUID rather than mint a duplicate.

Ambiguous records must be resolved before admission.

Example: the current `local_intel.entities` record named "Elm Farm" is typed as `place` while its evidence mixes farm, business, venue, and market concepts. It must not be blindly copied into Reality as the final Elm institutional identity.

## 14. Compatibility is one-way

The new core may temporarily read or map legacy Atlas data through `compatibility.legacy_bindings`.

Legacy identity / authority structures must never become dependencies of the new core.

Forbidden new-core dependencies include:
- `atlas.organizations`;
- `atlas.principals`;
- `atlas.organization_memberships`;
- `atlas.principal_ledger_authorities`;
- legacy Organization-as-identity assumptions;
- legacy owner-as-access assumptions.

The intended direction is:

```text
legacy Atlas
    ↓ migration / compatibility map
Reality + Personal Atlas + Ledger core
```

Never:

```text
new core
    ↓ authority dependency
legacy identity hierarchy
```

## 15. Foundational namespaces

The clean core begins in four private schemas:

### `reality`
Canonical real-world identity, relationships, contact routes, Auth→Person bindings, Entity claims, and claim challenges.

### `personal`
Native Personal Atlas state for human Persons.

### `ledger`
Practitioner-onboarded Ledgers, Seats, responsibilities, actions, observations, summaries, Ledger connections, and exposures.

### `compatibility`
One-way legacy-to-new mappings only. Compatibility is never an authority source.

## 16. First migration boundary

The first Reality / Ledger core migration intentionally does not migrate Elm, Feast Guild, Lex, or any public Entity.

It establishes the constitutional primitives and proves them with rollback-safe synthetic data.

Existing product surfaces remain on legacy architecture until a deliberate migration tranche cuts each surface over.

No new feature should add dependencies on Principal, Organization Membership, or Principal Ledger Authority. Those structures are now migration debt.

## 17. First real acceptance target

Elm + Lex will be the first real migration proof.

The target state is:

```text
Lex [canonical Person]
  ↓ Auth binding
Personal Atlas [native]

Elm Farm [canonical Entity]
  ├── Flower Ledger [practitioner-onboarded]
  └── Venue Ledger [practitioner-onboarded]

Lex
  ├── Seat → Flower Ledger
  └── Seat → Venue Ledger

Feast Guild [canonical Entity]
  ↓ eventually practitioner-onboarded
Feast Guild Ledger

Elm Flower Ledger
  ↓ summary exposure
Feast Guild Ledger

Elm Venue Ledger
  ↓ summary exposure
Feast Guild Ledger
```

This acceptance target must be achievable without using a Principal, Organization Membership, Principal Ledger Authority, or Organization-as-identity row as truth.


## 18. Instantiation checkpoint

The clean-room core is now instantiated in production through:

- `20260925014915_atlas_reality_ledger_core_v1`
- `20260925015101_atlas_reality_ledger_core_hardening_v1`

The new core is intentionally empty of real admitted subjects at this checkpoint:

- 0 Reality Entities;
- 0 new Ledgers;
- 0 new Seats;
- 0 Personal Atlases;
- 0 compatibility bindings.

Synthetic rollback-safe acceptance proves:

- Auth→Person binding creates native Personal Atlas;
- Ledger creation is blocked until practitioner onboarding reaches `ready_to_activate`;
- a claim challenge cannot use a contact route belonging to another Entity;
- only Person Entities may receive Seats;
- a source Ledger summary may be exposed to an observing Ledger;
- the clean core has zero foreign keys to `atlas` or `local_intel`.

Existing production product surfaces have not been cut over. Elm, Feast Guild, Lex, and Shared Intelligence identities have not yet been admitted into the new core.


## 19. First real cutover — Lex + Elm achieved

Production migrations:

- `20260925132140_atlas_reality_ledger_legacy_migration_case_v1`
- `20260925132343_atlas_reality_ledger_lex_elm_cutover_v1`
- `20260925132508_atlas_reality_ledger_elm_legacy_edge_retirement_v1`

The first real constitutional cutover is complete.

### Lex

Lex is admitted once as:

```text
reality.entities
id = 59e9fd9d-e7fd-48ca-91e0-ee271c05148e
kind = person
stable_key = lex
```

The existing Atlas Person UUID was preserved.

The existing Auth credential binds directly to that Reality Person through `reality.auth_person_bindings`.

That active Auth→Person binding created Lex's native Personal Atlas automatically.

No Principal is used by the new core.

The legacy Lex Principal is recorded in `compatibility.legacy_bindings` as retired architecture with no replacement authority object.

### Elm Farm

Elm Farm is admitted once as:

```text
reality.entities
id = de584041-a636-424d-b8f5-2ff90ba3685e
kind = business
stable_key = elm-farm
```

The existing Shared Intelligence UUID was preserved.

This was a **reconcile**, not a blind copy: the legacy Shared Intelligence record called Elm Farm a `place`, but its evidence and current institutional carrier establish that the row had been conflating the business/entity with physical-place attributes.

Reality therefore preserves the identity UUID while correcting the subject boundary to Elm Farm as the business/entity.

The former `atlas.organizations` Elm Farm row maps to this same Reality Entity; it does not survive as a second identity.

### Elm Ledgers

Two historical Ledger UUIDs were preserved:

```text
Elm Farm [Reality Entity]
  ├── Elm Farm Flower Ledger
  │     id = 0c5f53dd-3659-4fed-b8d7-a771a4172f36
  │     stable_key = elm-farm:flower
  │
  └── Elm Farm Venue Ledger
        id = 8df18008-28ef-48e9-babd-1eb0e0dd7e3c
        stable_key = elm-farm:venue
```

Both point directly to the single Elm Farm Reality Entity.

They do not point through an Organization.

The old Elm Farm Ledger contained 23 established farm/production entries. All 23 were preserved as `ledger.actions` with their original entry UUIDs and provenance.

The historical Venue Ledger had no `organization_ledger_entries`; therefore zero Venue actions were invented during migration.

### Lex Seats

Lex has one active Seat in each Elm Ledger.

Those Seats establish only:

> Lex participates in this Ledger.

The migration explicitly does not preserve the old `owner` membership role and does not preserve Principal Ledger Authority.

No real-world `Lex owns Elm Farm` relationship was created because the legacy software-authority records are not sufficient evidence for that reality claim.

### Legacy edge retirement

The old Elm sibling Ledger relation was not migrated into `ledger.connections`.

Two Ledgers sharing Elm Farm as their subject does not imply that one observes the other.

The old `atlas.ledger_relationships` sibling row is therefore recorded as retired compatibility semantics.

The two old `atlas.ledger_organization_participations` rows are also recorded as retired compatibility semantics because the new Ledgers point directly to Elm Farm.

### Current production checkpoint

At this checkpoint:

- Reality Entities: 2 — Lex and Elm Farm;
- active Auth→Person bindings: 1;
- native Personal Atlases: 1;
- new-core Ledgers: 2;
- active Seats: 2;
- migrated Flower/Farm actions: 23;
- Venue actions: 0;
- Ledger connections: 0;
- Ledger exposures: 0.

There are no structural `principal_id`, `organization_id`, membership-role, or owner-role columns anywhere in the `reality`, `personal`, or `ledger` schemas.

Legacy product tables remain physically present only so existing product surfaces continue working until each surface is deliberately cut over.


## Reality responsibility authority

Identity, participation, and authority are separate facts.

The canonical authority sequence is:

```text
known condition
→ explicit responsibility relation
→ jurisdiction
→ permitted operation set
→ execution
```

`reality.responsibility_relations` is the canonical Reality-era carrier for bounded responsibility.

A responsibility relation may be Entity-jurisdictional or domain-jurisdictional, but it must name its permitted operations and any narrower scope. No operation may be inferred merely because the Person has a Ledger Seat, an old Organization Membership, an old Principal record, a farm role, credentials, or access to a surface.

The authoritative implementation rules and first cutovers are documented in `architecture/ATLAS_REALITY_RESPONSIBILITY_AUTHORITY_V1.md`.


## Personal Atlas self-governance

Self-authored personal state is not institutional authority.

For personal capacity and household state, the canonical access path is `Auth → Reality Person → native Personal Atlas`. An explicit institutional responsibility is required only when the operation crosses into an institution or another governed jurisdiction.

Legacy Principal rows may temporarily carry storage for Personal Atlas data, but they do not establish identity or authority. See `architecture/ATLAS_PERSONAL_ATLAS_SELF_CAPACITY_CUTOVER_V1.md`.


## Personal Atlas portfolio-office projection

A Person's portfolio-office planning model is not automatically institutional Reality.

Owner-obligation, thesis, attention, modeled-function, scorecard, capital-request, and investment-opportunity records are Personal Atlas projections unless and until a separate governed promotion establishes institutional truth within explicit jurisdiction.

The canonical authoring membrane is `atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)`. Legacy Principal-named authoring RPCs are compatibility aliases only. See `architecture/ATLAS_PERSONAL_ATLAS_PORTFOLIO_OFFICE_CUTOVER_V1.md`.


## Correspondence identity authority

Correspondence identity administration follows custody.

Personal endpoints are governed by Reality Person + Personal Atlas. Institutional endpoints require an explicit Reality responsibility scoped to the canonical institution and exact communication endpoint. Legacy endpoint grants may remain as compatibility carrier constraints, but Organization Membership and generic role do not establish correspondence authority.

See `architecture/ATLAS_CORRESPONDENCE_IDENTITY_REALITY_AUTHORITY_CUTOVER_V1.md`.


## Institutional Communication Context

Institutional communication authority is resolved once at the endpoint membrane rather than reinvented per action.

The context is `Auth → Reality Person → Responsibility → institution → endpoint → operation`. Legacy endpoint grants remain routing/carrier constraints only.

Communication operations that create, transfer, complete, or cancel Company Work are not granted by communication authority. See `architecture/ATLAS_INSTITUTIONAL_COMMUNICATION_CONTEXT_V1.md`.

## Communication response Work

An institutional communication may establish that a response consequence exists, but endpoint authority does not assign that Work.

A bounded Reality responsibility may authorize a Person to convert an exact unresolved response case into Company Work and self-claim it. From that point forward, the exact active Work responsibility allocation governs response state and completion.

Direct assignment, handoff, and collaborator creation for another Person require receiver uptake and remain fail-closed until that contract exists.

See architecture/ATLAS_INSTITUTIONAL_COMMUNICATION_RESPONSE_WORK_V1.md.

## Company Work receiver uptake

Exact Work responsibility transfer is receiver-driven.

A current responsible Reality Person may create a bounded transfer offer, but responsibility remains with the source allocation until the target Reality Person accepts. Acceptance is recorded as receiver self_adoption from the exact offer; only then may the source allocation release.

Communication handoff terminates at this generic Company Work primitive and no longer assigns responsibility directly.

See architecture/ATLAS_COMPANY_WORK_RECEIVER_UPTAKE_V1.md.
