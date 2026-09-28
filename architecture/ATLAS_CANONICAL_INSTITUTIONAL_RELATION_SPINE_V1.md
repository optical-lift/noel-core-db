# Atlas Canonical Institutional Relation Spine v1

Status: governing implementation architecture  
Date: 2026-09-28

## Purpose

Atlas needs a canonical institutional relationship spine before applicability, Company Work custody, Principal claim admission, or Clock arbitration can safely depend on institutional structure.

The spine answers a bounded set of questions:

```text
Which canonical Person stands in relation to this institution?
Which Positions exist in this institution?
Which Responsibilities exist in this institution?
Who occupies which Position, and when?
Which Responsibilities are carried by which Position, and when?
```

It does not answer:

```text
What operation may this Person execute?
What Work is allocated to this Person?
What deserves this Person's attention now?
What should appear on Today?
```

Those remain separate governed layers.

## Constitutional distinctions

```text
Person != Auth account
institutional standing != Position appointment
Position != Person
Responsibility definition != execution authority
Position carries Responsibility != Person is authorized to execute every operation touching that Responsibility
relationship existence != applicability
applicability != Principal claim
Principal claim != Clock admission
```

A Person may exist and participate in institutional reality without an `auth.users` identity.

A customer title such as `Farm Steward`, `Executive Director`, `Treasurer`, or `Volunteer Coordinator` is data. It is not a platform type.

## Canonical representation

The spine deliberately reuses canonical Reality rather than creating a parallel Organization-person database.

### Canonical identities

- Person: `reality.entities(entity_kind='person')`
- Position: `reality.entities(entity_kind='position')`
- Responsibility definition: `reality.entities(entity_kind='responsibility')`
- Institution: an existing canonical non-Person Reality Entity acting as the institutional subject

The v1 institution role is semantic, not a new mandatory `entity_kind='organization'`. Existing canonical businesses, churches, associations, projects, and other institutional subjects must not be duplicated merely to satisfy one type label.

### Canonical relation families

The spine uses `reality.entity_relationships` for five exact families:

1. `institutional_standing`
   - subject: Person
   - object: Institution
   - metadata requires `standingKey`

2. `institution_has_position`
   - subject: Institution
   - object: Position
   - metadata requires `positionKey`

3. `institution_has_responsibility`
   - subject: Institution
   - object: Responsibility
   - metadata requires `responsibilityKey`

4. `occupies_position`
   - subject: Person
   - object: Position

5. `position_carries_responsibility`
   - subject: Position
   - object: Responsibility

The generic relationship table remains canonical storage. The institutional spine supplies the exact guards, establishment operations, temporal resolution, and provenance rules that the generic table alone cannot provide.

## Position and Responsibility identity

Positions and Responsibilities are durable semantic identities, not labels embedded in appointments.

A Position is scoped to one institution and keyed by an institution-local `positionKey`.

A Responsibility definition is scoped to one institution and keyed by an institution-local `responsibilityKey`.

Stable keys are deterministic:

```text
institution_position:<institution-uuid>:<position-key>
institution_responsibility:<institution-uuid>:<responsibility-key>
```

Changing a display label does not create a new Position or Responsibility identity.

Ending an appointment does not retire the Position.

Ending a Position→Responsibility relation does not retire either semantic identity.

## Institutional standing

`institutional_standing` records a direct Person↔Institution relationship independently of Position occupancy.

Representative standing keys are customer data:

- employee
- contractor
- volunteer
- board_member
- member
- officer
- advisor

Atlas does not infer execution authority from a standing key.

Atlas also does not require an institutional standing row before a Position appointment can be established. The two relations are separate facts and may be learned in either order.

## Temporal law

Normal historical ending does not erase or retire a relationship.

Canonical established relations use:

- `relationship_state='established'`
- `valid_from`
- optional `valid_until`

A relation is effective `as_of` time `T` when:

```text
relationship_state = established
and valid_from <= T
and (valid_until is null or valid_until > T)
```

`retired` and `disputed` remain reconciliation states, not substitutes for an ordinary historical end.

The spine exposes explicit `as_of` resolution. Downstream systems must not equate `valid_until is null` with universal timeless truth.

## Authority to establish institutional structure

Institutional structure is canonical truth and therefore requires explicit responsibility authority.

The v1 responsibility envelope is:

```text
responsibility_key = institution_structure_governance
jurisdiction_kind = entity
jurisdiction_entity_id = exact institution
```

Permitted operations are individually bounded:

- `institutional_standing.establish`
- `institution_position.establish`
- `institution_responsibility.establish`
- `position_appointment.establish`
- `position_responsibility.establish`
- `institution_relation.end`

The existing `reality.resolve_responsibility_relation_v1(...)` remains the authority resolver.

No authority is inferred from:

- old Organization Membership;
- old Principal state;
- Ledger Seat;
- institutional standing;
- Position occupancy;
- Responsibility definition;
- visibility;
- source-system role labels.

## Responsibility definition versus execution authority

This distinction is mandatory.

Example:

```text
Farm Steward carries Animal Care
```

means the Position is structurally associated with the Responsibility definition.

It does not, by itself, mean:

```text
Anna may execute animal_care.* operations
```

Execution authority remains a separate `reality.responsibility_relations` envelope with exact permitted operations and jurisdiction.

A later governed derivation may propose or establish such an authority envelope from institutional structure under its own rules, but this tranche does not infer or mint it.

## Establishment commands

The v1 membrane exposes exact commands for:

1. establish institutional standing;
2. establish a Position inside an institution;
3. establish a Responsibility definition inside an institution;
4. appoint a Person to a Position;
5. attach a Responsibility definition to a Position;
6. end one established spine relation at an explicit effective time.

Each command:

- resolves the authenticated caller to a canonical Reality Person;
- checks `institution_structure_governance` for the exact institution and operation;
- validates canonical entity kinds and same-institution scope;
- preserves structured establishment basis;
- records the authority relation used;
- is idempotent when the same active semantic relation already exists;
- creates no Auth account;
- creates no Ledger Seat;
- creates no Company Work allocation;
- creates no execution responsibility envelope.

## Relation immutability

For the five spine relation families:

- subject, object, relationship kind, `valid_from`, and establishment evidence are immutable after insert;
- normal ending may set `valid_until` exactly once;
- ending provenance is appended in metadata;
- an already-ended relation may not be reopened by editing history;
- corrected history requires a new governed relation plus reconciliation/supersession rather than mutation of the original meaning.

## Workbench integration

The Implementation Workbench receives new ESTABLISH routes for the institutional spine.

The Workbench still owns only request custody and routing.

```text
Workbench sentence
→ ESTABLISH route
→ reality.institutional_structure membrane
→ exact destination authority check
→ canonical consequence
→ canonical rerender
```

Registered v1 intent keys:

- `establish.institutional_standing`
- `establish.institution_position`
- `establish.institution_responsibility`
- `establish.position_appointment`
- `establish.position_responsibility`
- `establish.institution_relation_end`

Workbench route confirmation is not structural truth confirmation and does not satisfy destination authority.

## Relationship to Foundry admission

Foundry may establish and seal candidate institutional structure before Atlas admission.

This spine supplies exact destination operations for a subset of the baseline material the Foundry Admission Bridge previously had to leave pending:

- Person↔Institution standing;
- Position identity;
- Responsibility identity;
- Person↔Position appointment;
- Position↔Responsibility relation.

Foundry evidence still does not bypass Atlas admission or destination authority.

## Relationship to future applicability

Applicability may later resolve facts such as:

```text
Person occupies Position as_of T
Position carries Responsibility as_of T
Person has institutional standing as_of T
```

and derive a bounded proposition such as:

```text
this requirement applies to this Person because of this exact effective relation path
```

That derivation belongs downstream of this spine.

## Relationship to Company Work

Company Work may later use canonical Reality Person identity plus resolved institutional structure without treating legacy Organization Membership UUIDs as semantic custody.

This tranche does not migrate Company Work storage yet.

## Relationship to Principal and Clock

The spine supplies relationship facts only.

The future sequence remains:

```text
canonical institutional relation
→ typed temporal Relation Resolution
→ applicability
→ lawful Principal claim
→ Clock admission
→ Today projection
```

Clock must never infer ownership or attention entitlement merely because a Person occupies a Position.

## Acceptance criteria

The tranche is valid only when:

1. a target Person does not require an Auth account;
2. Position and Responsibility are canonical Reality identities rather than customer-specific schema types;
3. the five relation families are structurally guarded;
4. Position and Responsibility keys are institution-local and deterministic;
5. Person↔Position and Position↔Responsibility require same-institution scope;
6. all establishment operations require exact entity-jurisdiction responsibility authority;
7. institutional standing and Position occupancy do not themselves grant execution authority;
8. Position→Responsibility does not create `reality.responsibility_relations`;
9. ordinary historical ending preserves the relation as established history with `valid_until`;
10. explicit `as_of` resolution exists;
11. Workbench exposes deterministic ESTABLISH routes without gaining destination authority;
12. no Organization Membership, Principal, role, Ledger Seat, or Auth-account dependency is required to represent the target Person or institutional relation;
13. no generic SQL/CRUD route is introduced;
14. the same grammar can represent unrelated institutions without code changes.

## Governing shorthand

> **Institutional structure is Reality, not access.**

> **Positions carry responsibilities. People occupy positions. Authority remains separately established.**

> **Resolve the relationship first. Derive applicability later. Admit attention last.**
