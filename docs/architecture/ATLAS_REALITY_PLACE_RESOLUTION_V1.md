# ATLAS_REALITY_PLACE_RESOLUTION_V1

## Purpose

Establish a universal, source-aware way for Atlas to resolve named geography into reusable canonical Reality Place entities without relying on free-text location matching or duplicating the same place across research sources.

This contract extends ATLAS_REALITY_PLACE_CONTEXT_V1 and the Reality Relationship / Entity Topology substrate. It is not an Elm-specific geography feature.

## Governing laws

1. A Place is a canonical `reality.entities` subject with `entity_kind = 'place'` plus an active governed Place profile.
2. Display names are not identity keys. `Springfield` alone is never sufficient to establish or resolve a Place.
3. Source identity is explicit. A source namespace + source key may bind to exactly one canonical Place Entity.
4. Multiple source identity keys may bind to the same Place after identity convergence.
5. Reusing a source identity key with different Place semantics fails closed.
6. Existing canonical Place identity is reused before any new Place Entity is admitted.
7. Source evidence may establish a Place profile only through a governed adapter whose evidence and basis are preserved.
8. Source geography does not become spatial truth about another entity merely because both records contain matching text.
9. Entity→Place assertions enter Reality through the existing relationship proposition/evidence/adjudication membrane.
10. An adapter may auto-adjudicate only when its source authority is itself canonical Atlas truth. Shared Intelligence geography remains proposal-only in v1.
11. Resolution must distinguish `resolved`, `absent`, and `ambiguous`; ambiguity must never silently choose a candidate.
12. Canonical Place resolution is reusable across all Ledgers, searches, target definitions, and applications.

## Universal identity model

`reality.place_identity_keys` binds external/source identity to canonical Place identity:

- `entity_id`
- `identity_namespace`
- `identity_key`
- `identity_state`
- `evidence`
- `identity_basis`
- `metadata`

The active pair `(identity_namespace, identity_key)` is globally unique.

Examples of namespaces may include:

- `local_intel.geographic_areas`
- `us_census.place_geoid`
- `us_gnis.feature_id`
- another governed provider-specific namespace

The namespace does not determine truth authority by itself. Evidence and admission policy remain explicit.

## Resolution order

1. Exact canonical Reality Entity id, when supplied.
2. Active source identity key.
3. Exact governed source adapter lookup whose scope is sufficiently disambiguated.
4. Otherwise `absent` or `ambiguous`.

Name-only fuzzy resolution is out of scope for v1.

## Shared Intelligence geography adapter

`local_intel.geographic_areas` is an evidence carrier, not canonical Reality.

For a source-verified geographic area, Atlas may:

1. resolve an existing `local_intel.geographic_areas` identity key;
2. otherwise admit one canonical Place Entity;
3. establish a governed Place profile preserving source URL, source id, source stable key, coordinates, precision, and verification state;
4. bind the Shared Intelligence area identity key to that canonical Place.

The adapter must not infer country silently when the source record does not contain it; the caller supplies a governed country code in v1.

## Entity geography adapter

`local_intel.entity_geographic_areas` may be converted only into an open Reality relationship proposition when:

- the referenced geographic area resolves to a canonical Place;
- the source entity already resolves to a canonical Reality Entity;
- the relation kind is supported (`located_in` in v1);
- the source assertion is current enough to be considered by the adapter.

Derived source assertions remain derived evidence. They are not auto-adjudicated.

## Out of scope

- geocoding arbitrary text
- route calculation
- radius calculation
- polygon storage
- fuzzy place-name search
- automatic merge of conflicting places
- automatic promotion of every Shared Intelligence geography row
- contact qualification or outreach
- Elm-specific corridor definitions

## Acceptance criteria

The v1 tranche is complete when Atlas can prove all of the following:

1. a source-verified Shared Intelligence locality is admitted once and reused idempotently;
2. the same source identity key cannot point at two Places;
3. an ambiguous exact-name source lookup fails closed;
4. the resulting Place has a governed profile and source identity receipt;
5. a Shared Intelligence entity→locality assertion creates an open Reality relationship proposition only;
6. no spatial relationship is established until adjudication;
7. rollback fixtures leave no Place, identity-key, proposition, evidence, or relationship residue.
