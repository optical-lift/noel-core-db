# Atlas Institutional Temporal Relation Resolution v1

Status: governing implementation architecture  
Date: 2026-09-28

## Purpose

The Canonical Institutional Relation Spine establishes durable institutional relation history. This tranche defines the read boundary that allows Atlas to ask what that history warrants at one explicit `as_of` without turning a current snapshot, UI state, ownership fact, Ledger Seat, or Clock projection into institutional truth.

The governing sequence is:

```text
canonical institutional relation history
→ bounded source read
→ typed adapter
→ durable governed basis
→ explicit as_of
→ pure Relation Resolution
→ structural assertions / unresolved / conflicts
```

This tranche does not establish applicability, execution authority, Company Work custody, Principal claims, Clock admission, or Today placement.

## Source authority

The canonical source remains:

- `reality.entities`; and
- the five guarded institutional relation families in `reality.entity_relationships`.

Relation Resolution does not become a new source table and does not cache a second institutional graph.

The source read is history-complete for one exact canonical Person + one exact canonical Institution scope. It may return:

- direct Person→Institution standing history;
- Institution→Position scope history;
- Institution→Responsibility scope history;
- Person→Position appointment history for Positions belonging to that Institution;
- Position→Responsibility history for Positions and Responsibilities belonging to that Institution;
- the canonical Position and Responsibility identities referenced by those rows.

The source read preserves disputed/retired relation rows as source history. Only the relation evaluator decides whether a supplied row warrants a present assertion, an unresolved condition, or no current assertion at the requested `as_of`.

## Completeness receipt

The read envelope itself is durable basis.

A complete read states that Atlas successfully read the bounded canonical history for the exact Person and Institution. This receipt is what can warrant a bounded negative proposition such as "no effective appointment was present in this complete history at T."

Missing data because a request failed, the UI did not load, or no read was supplied must remain unresolved. Absence of a relation row is not a negative assertion unless the complete bounded read is itself supplied.

## Explicit time

Resolution time is never hidden.

The application supplies an explicit `as_of` to the shared Relation Resolution kernel. The source read may have a `capturedAt` timestamp, but `capturedAt` is provenance for the read; it is not the semantic time being resolved.

The effective interval rule remains:

```text
relationship_state = established
and valid_from <= as_of
and (valid_until is null or valid_until > as_of)
```

A disputed relation whose interval covers `as_of` produces unresolved/disputed state for the bounded question it affects. A retired relation does not silently become current merely because its historical interval would otherwise contain the coordinate.

## Typed receiving questions

The application adapter exposes separate relation questions rather than one generic `ResolvedRelation` graph.

### Institutional standing

Question:

> What direct institutional standing, if any, does this Person have with this Institution at T?

Possible structural assertions preserve:

- Person;
- Institution;
- standing key;
- exact standing relation ID;
- exact effective interval.

### Position appointment

Question:

> Which Institution-scoped Positions does this Person occupy at T?

An appointment assertion requires both:

- an effective `occupies_position` row; and
- an effective `institution_has_position` scope row for the exact same Position and Institution.

The exact two support relation IDs remain attached.

### Position responsibility

Question:

> Which Institution-scoped Responsibilities does this Position carry at T?

A structural assertion requires:

- effective Position scope;
- effective Responsibility scope; and
- effective `position_carries_responsibility` relation.

All three source relation IDs remain attached.

### Person structural responsibility path

Question:

> Through currently effective institutional structure, which Responsibility definitions are connected to this Person at T?

This is a structural path only:

```text
Person occupies Position
+ Position belongs to Institution
+ Position carries Responsibility
+ Responsibility belongs to Institution
→ Person is structurally connected to Responsibility at T
```

It is explicitly not an execution-authority result. It must never satisfy `reality.resolve_responsibility_relation_v1(...)`, mint permitted operations, create Work allocation, or create a Principal claim.

## Conflict and dispute law

The resolver must preserve conflicts rather than picking a preferred row.

Examples:

- a disputed effective appointment competes with established history;
- one Position resolves to incompatible institution scope at the same `as_of`;
- a Position→Responsibility link is effective but one required scope relation is disputed;
- source identities are canonical but the exact structural path is not sufficiently warranted.

The shared Relation Resolution kernel owns only envelope validation and support-ref integrity. Institutional semantics remain in the institutional adapter.

## Read membrane

The database exposes a bounded authenticated read for the signed-in canonical Person:

`atlas.institutional_relation_history_self_api_v1(p_institution_entity_id uuid)`

The membrane:

- resolves `auth.uid()` to the canonical Reality Person;
- requires an exact canonical Institution;
- returns only that Person's institutional relation history for that Institution;
- returns canonical Position/Responsibility identities referenced by that bounded history;
- creates no relationship, access, authority, Work, Principal claim, or Clock state;
- exposes no raw table mutation;
- carries a completeness boundary in the response.

A separate practitioner or cross-Person read membrane may be added later under its own disclosure/authority law. v1 does not use service role as a generic human-structure reader.

## Non-implications

A resolution assertion does not imply:

- employment unless the source standing itself says so;
- execution authority;
- Ledger participation;
- source visibility;
- Company Work responsibility;
- requirement applicability;
- attention entitlement;
- Clock admission;
- Today placement.

In particular:

```text
Person structurally connected to Responsibility
!=
Person carries an execution responsibility envelope
```

## Application boundary

The Atlas adapter must consume the governed source read, not reconstruct institutional structure from browser-owned rows or unrelated projections.

Each normalized basis item retains:

- exact source relation or read-envelope ref;
- source owner ref;
- Person/Institution subject refs where relevant;
- source relation state;
- effective interval;
- provenance indicating the canonical read membrane.

The pure evaluator receives no hidden database access and no wall clock.

## Acceptance criteria

This tranche is accepted only when:

1. source history remains canonical in Reality, with no resolution cache table;
2. one exact Person + Institution read is explicitly complete for the five spine relation families;
3. the application uses an explicit `as_of` distinct from read capture time;
4. no missing fetch/read is translated into a negative structural assertion;
5. direct standing, appointment, Position Responsibility, and Person structural Responsibility are separate typed outputs;
6. exact support relation IDs are preserved in every positive structural assertion;
7. disputed effective source history remains unresolved/disputed;
8. historical `valid_until` is respected without rewriting history;
9. Position occupancy cannot become execution authority;
10. Position→Responsibility cannot become execution authority;
11. no owner, Principal, Ledger Seat, Organization Membership, role label, or Clock state participates in structural resolution;
12. no Company Work allocation, applicability result, Principal claim, or Today item is created;
13. the shared `relation-resolution.ts` kernel requires no institutional vocabulary change;
14. the same adapter works for unrelated institutions without customer-specific code.

## Governing shorthand

> **Read history completely. Resolve time explicitly. Preserve every support edge.**

> **Structure can explain why a relationship path exists. It cannot invent authority from that path.**
