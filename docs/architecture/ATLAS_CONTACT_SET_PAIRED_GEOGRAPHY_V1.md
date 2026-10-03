# ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1

## Purpose

Add a universal contact-set geography mode for organization-first prospect qualification where the same normalized operating organization must have governed presence in two independently defined Place sets.

This contract replaces neither ordinary local search nor the general Target Intelligence language. It adds one explicit execution mode that consumes the canonical Reality Place and operating-topology substrates.

## Geography envelope

A paired request uses:

```json
{
  "mode": "paired_operating_presence",
  "sideA": {
    "places": [
      {"name":"Joplin","administrativeHint":"MO","countryCode":"US","placeKind":"locality"}
    ]
  },
  "sideB": {
    "places": [
      {"name":"Rolla","administrativeHint":"MO","countryCode":"US","placeKind":"locality"}
    ]
  },
  "maxOperatingDepth": 8,
  "maxSpatialDepth": 8
}
```

A Place reference may instead use either:

- `placeEntityId`, or
- `identityNamespace` + `identityKey`.

Name-based references must include sufficient administrative/country disambiguation for the governed source adapter. Name-only fuzzy resolution is forbidden in v1.

## Governing laws

1. `placeLabels` retains its existing ordinary local-search meaning. Paired geography never falls back to `placeLabels` or address substring matching.
2. Paired geography is organization-first in v1. It qualifies operating roots before any person/contact discovery stage.
3. Both Place sets must resolve to canonical Reality Places before paired qualification can run.
4. Unresolved or ambiguous Place references create `geography_resolution_gap`; they do not produce a negative organization result.
5. A qualifying organization must have one canonical normalized operating root with an independently proven presence path into side A and side B.
6. Two unrelated one-sided organizations may never combine into a paired match.
7. Only established/observed canonical Reality relationships may satisfy the paired proof. Open Shared Intelligence propositions are evidence, not qualification.
8. Missing operating/spatial proof is UNKNOWN and produces `paired_operating_presence_gap`; it is not FALSE.
9. Organization qualification is independent of phone/email/person coverage. Missing contact fields are downstream enrichment gaps only after the organization qualifies.
10. Corporate-control, franchise, chapter, and brand axes do not satisfy the direct operating-root requirement unless a separate governed rule explicitly says so.
11. The paired search result must retain side-A and side-B proof paths.
12. No paired search authorizes communication.

## Resolution states

Paired geography preparation returns:

- `resolved` — both sides have at least one canonical Place;
- `needs_acquisition` — one or more references are absent/ambiguous/invalid.

The execution layer persists exact resolution gaps so future acquisition can target the missing Place identity rather than rerunning a broad organization search.

## Organization qualification result

The paired directory result is organization-level and returns:

- canonical operating-root Entity id;
- organization name/kind;
- side-A proof paths;
- side-B proof paths;
- organization-level known contact routes;
- private requesting-Ledger overlay;
- field coverage state.

Person/function discovery is downstream of this qualification stage.

## Gap kinds

### `geography_resolution_gap`
The requested named/source Place cannot yet resolve uniquely to a canonical Reality Place.

### `paired_operating_presence_gap`
The Place sets are resolved but Reality does not yet establish enough same-root operating/spatial proofs to satisfy the requested population.

### Existing field gaps
After organization qualification, missing website/phone/email/etc. remain normal entity field gaps.

## Acceptance criteria

1. ordinary `placeLabels` search behavior remains unchanged;
2. paired requests validate a strict geography envelope;
3. known Place references resolve/admit once and are reused;
4. unresolved Place references yield exact geography gaps rather than SQL failure;
5. a synthetic spanning organization is returned once;
6. unrelated A-only and B-only organizations do not combine;
7. open propositions do not qualify;
8. preparation persists paired geography receipts and exact gaps;
9. no communication or Ledger relationship is created merely by qualification;
10. rollback fixture leaves no synthetic data residue.
