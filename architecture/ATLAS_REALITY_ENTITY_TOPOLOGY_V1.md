# ATLAS REALITY ENTITY TOPOLOGY V1

## Status
Candidate architecture contract.

## Purpose

Atlas already has a governed canonical relationship substrate. This tranche establishes the universal semantics required to reason over those relationships as topology without turning one customer's search problem into Reality law.

The component answers questions such as:

- what larger entity or entities does this entity belong to?
- along which structural axis?
- which descendants constitute operational or contextual presence for a root entity?
- can a proposed structural relationship be accepted without creating an illegal cycle or violating parent cardinality?
- what proof path caused a topology result?

Elm's regional-midpoint search is an acceptance case only. No Elm-specific geography, sales, venue, corridor, pricing, or prospect vocabulary belongs in this contract.

## Governing distinction

A canonical relationship states a proposition about Reality.

Topology semantics state how a governed relationship kind may participate in structural traversal.

A Ledger Target may consume that traversal for a private purpose, but topology does not itself establish prospect status, ranking, communication authority, or Ledger meaning.

## Laws

### 1. Relationship truth remains canonical Reality

Topology MUST read `reality.entity_relationships` admitted through the relationship proposition/evidence/adjudication membrane. It MUST NOT treat legacy or unadjudicated relationship data as canonical solely because the traversal engine can see it.

### 2. Topology semantics belong to relationship kinds

A relationship kind MAY be assigned universal topology semantics:

- topology axis
- structural/non-structural role
- parent direction
- transitivity
- presence propagation
- default presence class/effect

The semantics are independent of any Ledger or search.

### 3. Parentage is axis-specific

Atlas MUST NOT assume every entity has one universal parent.

An entity may lawfully have different parents on different axes, for example:

- operating structure
- ownership
- brand/franchise
- institutional containment
- geographic containment

A topology axis declares whether multiple simultaneous parents are permitted within that axis.

### 4. Structural cycles fail closed

For an acyclic topology axis, admission of a relationship that would create a cycle MUST fail before canonical relationship materialization.

Direct self-links remain prohibited by the relationship substrate. This tranche additionally prohibits indirect structural cycles such as `A -> B -> C -> A` when the axis is acyclic.

### 5. Traversal is explicit and bounded

Recursive traversal MUST:

- name an axis or intentionally allow all active axes;
- name a direction (`ancestors` or `descendants`);
- use a bounded maximum depth;
- preserve the complete proof path;
- ignore retired/inactive semantics;
- honor relationship validity windows;
- distinguish canonical relationship states.

### 6. Presence is derived, not copied into identity

A root entity may have presence through descendants when the traversed relationship kinds explicitly propagate presence.

Presence propagation MUST NOT be inferred from English labels alone.

A topology semantic may declare:

- no presence effect;
- direct presence;
- conditional presence;
- contextual presence.

This is Reality-side structural meaning. A Ledger remains free to decide which presence classes/effects satisfy its own purpose.

### 7. Proof paths are first-class output

Every derived ancestor, descendant, or presence result MUST retain enough information to reconstruct why Atlas reached it:

- starting entity;
- related entity;
- depth;
- entity path;
- relationship-id path;
- relationship-kind path;
- topology-axis path;
- relationship-state path.

### 8. Missing topology is not false

Target Intelligence remains open-world.

If no qualifying canonical topology path is known, Atlas MUST NOT automatically conclude that no such path exists. A topology-dependent target predicate may therefore evaluate `UNKNOWN` and produce a precise evidence obligation.

### 9. Set algebra belongs to Target Intelligence

Reality provides topology. Ledger Target Intelligence composes predicates over it.

The universal target language may use `ALL`, `ANY`, `NOT`, and `AT_LEAST_N` over independent topology predicates. Paired geography is therefore an application of generic set algebra rather than a geography-specific operator.

### 10. Legacy Shared Intelligence is evidence, not automatic canonical truth

Existing `local_intel` hierarchy/location data may be used to propose canonical entities and relationships through governed admission. It MUST NOT be bulk-copied into Reality merely because a topology slot exists.

## Core objects

### `reality.topology_axes`

Registry for structural axes and their invariants.

Minimum semantics:

- `topology_axis`
- display/description
- `allows_multiple_parents`
- `cycle_policy`
- active/retired state

### `reality.relationship_topology_semantics`

One optional topology interpretation per governed relationship kind.

Minimum semantics:

- relationship kind
- topology axis
- structural flag
- parent direction
- transitive flag
- presence propagation flag
- presence effect
- default presence class

### Traversal service

`reality.entity_topology_paths_service_v1(...)`

Returns bounded, proof-bearing ancestor or descendant paths.

### Presence service

`reality.entity_presence_paths_service_v1(...)`

Returns only paths whose relationship semantics propagate presence.

## Initial target-language extension

This tranche may extend Ledger Target Intelligence with:

- `at_least_n`
- `topology_path_exists`

`topology_path_exists` evaluates a nested endpoint predicate over canonical topology endpoints. If no matching path is established, the result remains `UNKNOWN` unless another deterministic branch makes the enclosing expression determinate.

## Non-goals

This tranche does NOT establish:

- a geography ontology;
- route or driving-time calculations;
- Elm prospect rules;
- sales ranking;
- contact discovery;
- outreach authorization;
- automatic promotion of `local_intel` data;
- one universal parent per entity;
- a generic machine-learning score.

## Acceptance cases

The validation suite must prove at least:

1. one-hop ancestor traversal;
2. multi-hop ancestor traversal;
3. descendant traversal;
4. legal multiple parents on different axes;
5. cardinality enforcement on a single-parent axis;
6. indirect-cycle rejection;
7. presence propagation only across opted-in relationship kinds;
8. proof paths contain all traversed relationship IDs;
9. `topology_path_exists` returns TRUE for a known matching path;
10. missing matching topology returns UNKNOWN with one precise obligation;
11. `AT_LEAST_N` prunes obligations when already determinately true or false;
12. no fixture state persists after rollback.

## Architectural boundary

The intended flow is:

`evidence -> relationship proposition -> adjudication -> canonical relationship -> topology traversal -> Ledger-private target evaluation -> evidence obligation if unresolved`

No step is permitted to collapse the next step into itself.
