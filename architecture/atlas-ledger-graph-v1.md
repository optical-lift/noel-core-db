# Atlas Ledger Graph v1

Status: governing implementation contract for the next Atlas database tranche.

## Purpose

Atlas must model a Ledger as an independently governed reality, not as a child object owned by one Organization. A Ledger exists because a distinct endeavor or operating reality needs its own governing rules, authority, methods, responsibilities, and history.

Organizations, people, properties, farms, venues, projects, franchises, shared services, groups, and other endeavors may participate in any number of Ledgers. Ledgers may relate to other Ledgers without collapsing their separate truth.

This tranche generalizes the first-class Ledger foundation before any Elm / Feast Guild custody adjudication.

## Governing laws

1. **Ledger identity is independent.** A Ledger does not derive its identity from an Organization, Organization name, domain, payment, login, or another Ledger.
2. **Names are labels, not identifiers.** New Organization and Ledger canonical identities and stable keys must be opaque and non-semantic. Renaming an endeavor must not change identity.
3. **A Ledger is a governing boundary.** Create a Ledger when reality needs independent rules, authority, methods, responsibilities, or operational history.
4. **Organization and Ledger are many-to-many concepts.** An Organization may participate in zero, one, or many Ledgers. A Ledger may involve zero, one, or many Organizations.
5. **Ledger relationships are explicit graph edges.** Parent/child, sibling, dependency, overflow, franchise, shared-service, group-membership, supply, and other relationships must be recorded as relationships rather than inferred from naming or containment.
6. **Cross-Ledger correlation does not merge truth.** Atlas may state that governed reality in Ledger A corresponds to governed reality in Ledger B while preserving the independent authority, provenance, and history of both sides.
7. **Authority is many-to-many.** Any number of Principals may hold root governing authority over any number of Ledgers. Authority does not depend on Organization membership.
8. **Commerce attaches to governed reality.** Purchase and entitlement may bind capability to an existing Ledger but may not manufacture Ledger identity or authority.
9. **Historical compatibility is preserved, not canonized.** Existing Organization-linked Ledgers remain valid historical rows while their Organization relation is moved into the explicit participation graph.
10. **Custody adjudication follows evidence.** The historical mixed Feast Guild container must not be used as ownership proof when Elm / Venue / Feast Guild realities are separated later.

## Canonical primitives

### Ledger

The governed reality itself.

Minimum durable identity:
- opaque `id` UUID;
- opaque `stable_key` generated independently of human-readable labels;
- human-readable `name`/label;
- general `ledger_kind` rather than `organization_governing` only;
- lifecycle status;
- metadata/provenance.

A Ledger has no mandatory owning Organization.

### Organization ↔ Ledger participation

A separate relation records institutional participation in a Ledger.

Examples of participation kinds may include:
- `governing`;
- `operating`;
- `member`;
- `sponsor`;
- `shared_service`;
- `franchisor`;
- `franchisee`;
- `supplier`;
- `customer`;
- `other`.

The relation is evidence-bearing and time-bounded. It must not imply Principal authority.

### Ledger ↔ Ledger relationship

A directed or symmetric graph edge between two Ledgers.

Relationship kinds are extensible. Initial governed kinds should support at least:
- `parent_of`;
- `sibling_of`;
- `depends_on`;
- `supplies`;
- `receives_overflow_from`;
- `franchise_of`;
- `member_of_group`;
- `shared_service_for`;
- `other`.

Directionality is explicit. Symmetric relationships must be represented or normalized consistently by contract rather than inferred by the UI.

### Ledger correlation

A correlation states that a specific governed subject in one Ledger corresponds to a specific governed subject in another Ledger.

A correlation is not foreign-key ownership and does not move or merge either subject.

Each side needs an address capable of naming reality without requiring every domain table to add Ledger-specific columns immediately. V1 uses a governed typed address:
- `ledger_id`;
- `subject_kind`;
- `subject_id` (UUID when the canonical object has one);
- optional `subject_key` for governed non-UUID addresses;
- optional `path` / semantic selector for a narrower part of the subject.

The edge records:
- correlation kind;
- directionality;
- status/effective period;
- basis/evidence;
- metadata.

Examples:
- Elm Farm production lot ↔ Feast Guild supply lot (`supplied_as`);
- Elm Venue event ↔ Elm Farm bouquet allocation (`consumes`);
- responsibility in one Ledger ↔ responsibility in another (`corresponds_to`).

### Principal ↔ Ledger authority

`atlas.principal_ledger_authorities` remains the canonical direct authority relation in v1. It already supports many Principals across many Ledgers.

This tranche must preserve:
- multiple active Principals on one Ledger;
- one Principal governing multiple Ledgers;
- root authority independent of Organization membership;
- explicit basis and lifecycle.

A future authority-group abstraction may reduce repetitive grant management, but groups must project to or resolve through the same effective Person/Principal ↔ Ledger authority truth. Ledger Graph v1 does not need to invent group identity merely to support the many-to-many authority matrix already available.

## Compatibility transition

Current production constraints encode an obsolete law:

```text
Ledger.organization_id NOT NULL
UNIQUE (Ledger.organization_id)
Ledger.ledger_kind = organization_governing
Organization insert -> automatically manufactures one same-key Ledger
```

Ledger Graph v1 replaces that with:

```text
Ledger
  ↕ explicit participation
Organization

Ledger
  ↕ typed relationship
Ledger

Ledger subject
  ↕ typed correlation
Ledger subject

Principal
  ↕ explicit authority
Ledger
```

Existing production Ledgers are preserved. Their current `organization_id` relationship is backfilled into the explicit Organization↔Ledger participation table before the legacy column becomes compatibility-only / nullable.

## Organization establishment compatibility

The existing noncommercial Organization-establishment API must continue to work during transition, but it must no longer depend on name-derived identity or the obsolete uniqueness constraint.

For compatibility, establishing a new Organization may still establish an initial Ledger in the same transaction, but this is a workflow choice, not a universal cardinality law. The result must be represented as:

1. opaque Organization identity;
2. opaque Ledger identity;
3. explicit Organization↔Ledger participation edge;
4. explicit Principal↔Ledger root authority.

Additional Ledgers may later be established for the same Organization without creating another Organization.

## Opaque identity rule

For new institutional roots:
- UUID remains the primary canonical identifier.
- `stable_key` must be opaque and non-semantic, e.g. a random token derived independently of the name.
- Names such as `Elm Farm`, `Elm Venue`, and `Feast Guild` remain mutable display labels only.
- Do not create stable keys such as `elm_farm`, `elm-farm`, `feast_guild`, `feast-guild`, or other name-derived slugs for new roots.

Existing historical semantic stable keys remain as provenance-compatible legacy data unless separately adjudicated.

## Tranche scope

Ledger Graph v1 must:

- generalize `atlas.ledgers` so `organization_id` is no longer mandatory and one Organization may participate in multiple Ledgers;
- broaden `ledger_kind` beyond `organization_governing`;
- add a human-readable Ledger name if not already available;
- add explicit Organization↔Ledger participation;
- backfill existing Organization/Ledger association into participation without changing existing Ledger IDs;
- add Ledger↔Ledger relationships;
- add cross-Ledger correlations;
- preserve `principal_ledger_authorities` as the direct many-to-many authority relation;
- replace name-derived identity for newly established Organizations/Ledgers with opaque stable keys;
- revise Organization-birth compatibility so it records participation instead of relying on one-Ledger-per-Organization uniqueness;
- preserve current commerce binding behavior against existing Ledger IDs;
- preserve browser security boundaries.

Ledger Graph v1 must **not**:

- move Elm, Venue, Feast Guild, Waiting Room, Nathan/Camp Duffel, rehabilitation research, or any other historical production rows;
- create the final Elm Farm, Elm Venue, or Feast Guild Ledgers yet;
- delete or archive the legacy mixed container yet;
- infer cross-Ledger correlations for historical data automatically;
- create authority groups unless a later concrete requirement shows the direct many-to-many authority model is insufficient;
- make commerce authoritative for identity.

## Required proofs

Production-shaped validation must prove:

1. all preexisting Ledger IDs and current Principal authority grants survive unchanged;
2. historical Organization↔Ledger associations are represented by explicit participation rows;
3. one Organization can participate in at least two active Ledgers;
4. one Ledger can have at least two participating Organizations;
5. an independent Ledger can exist with no Organization participant;
6. five Principals can simultaneously hold root authority across ten Ledgers using the existing authority relation without conflict;
7. typed Ledger relationships can represent directional and symmetric graph edges without cycles being prohibited merely because a cycle exists;
8. cross-Ledger correlations preserve distinct source and target reality addresses;
9. same correlation retry is idempotent while contradictory duplicate identity fails closed;
10. new Organization/Ledger stable keys are opaque and not derived from supplied names;
11. existing Organization establishment still produces a usable initial Ledger + participation + root authority transactionally;
12. commercial binding continues to target a specific existing Ledger and creates no institutional identity;
13. `anon` gains no new write/read capability to graph or authority tables;
14. authenticated access occurs only through governed APIs explicitly intended for browser use.

## Next tranche after Ledger Graph v1

Only after this graph is live should Atlas perform the Elm / Venue / Feast Guild custody adjudication:

- reclassify the historical `feast_guild` organization as an archived legacy Principal/portfolio container;
- archive Waiting Room Farm test reality;
- archive owner-level Nathan/Camp Duffel and rehabilitation research reality;
- create fresh opaque institutional identities where needed;
- create independent Elm Farm, Elm Venue, and Feast Guild Ledgers;
- establish Lex's root authority over Elm and Feast Guild Ledgers as directed;
- establish Anna only in Elm employment reality;
- leave Feast Guild operationally empty except for governing authority;
- preserve historical record IDs/provenance while assigning correct canonical Ledger custody;
- establish explicit correlations only where evidence says reality crosses Ledger boundaries.
