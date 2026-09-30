# ATLAS REALITY PLACE CONTEXT V1

## Status
Candidate architecture contract.

## Purpose

Atlas needs canonical spatial meaning without treating city/state strings, mailing addresses, venue records, or one customer's search geography as Reality law.

This tranche establishes Place as a typed extension of canonical `reality.entities`, defines universal spatial-containment relationships, and provides a governed compatibility bridge from Shared Intelligence geographic areas into Reality.

Elm and regional prospecting are acceptance cases only.

## Laws

### 1. Place is an Entity, not a string

A Place MUST first exist as one canonical `reality.entities` record with `entity_kind='place'`.

Names such as `Springfield`, `St. Louis`, or `Missouri` are labels, not identity by themselves.

### 2. Physical sites and geographic areas are distinct Place kinds

A physical venue/site and a locality/administrative region may both be Places, but they are not the same kind of thing.

The Place profile MUST preserve this distinction through a governed place-kind registry.

### 3. Place profile does not create identity

A Place profile extends an already-canonical Place Entity with spatial semantics. It MUST NOT create a second identity record or silently convert another Entity kind into Place.

### 4. Coordinates are evidence-bearing spatial attributes, not identity

Latitude/longitude and precision may help spatial reasoning, but they do not establish Place identity by themselves. Coordinate pairs MUST be stored with their precision/basis.

### 5. Spatial containment uses canonical relationships

Universal spatial structure is expressed through the Reality Relationship Substrate and Entity Topology:

- `located_in`: an Entity is spatially located within a Place;
- `contained_in`: one Place is spatially contained within another Place.

Both participate in the `spatial_containment` topology axis.

### 6. Spatial containment is open-world

Absence of a known `located_in` or `contained_in` path does not mean the relationship is false. Target Intelligence therefore remains capable of returning UNKNOWN and an evidence obligation.

### 7. Spatial hierarchy may have multiple parents

A Place may legitimately participate in more than one spatial hierarchy or containment context. The `spatial_containment` axis permits multiple parents but remains acyclic.

### 8. Place membership is transitive

If an Entity is `located_in` Place A and Place A is `contained_in` Place B, Atlas may derive a proof-bearing spatial path from the Entity to Place B.

The original relationships remain the canonical facts; transitive membership is a derived result.

### 9. Spatial results preserve proof

Every derived spatial membership MUST retain the canonical relationship IDs and entity path used to establish it.

### 10. Shared Intelligence is an adapter source, not spatial authority

`local_intel.geographic_areas`, entity city/state strings, and `entity_geographic_areas` may supply evidence and identity candidates.

They MUST NOT be silently copied into Reality as established truth.

### 11. Shared Intelligence geographic-area admission is identity-only

A compatibility adapter MAY preserve the Shared Intelligence geographic-area UUID as the Reality Entity UUID and create a source-backed Place profile.

The adapter MUST NOT create Ledger relevance, prospect status, outreach authority, or organization-specific qualification metadata.

### 12. Entity-to-area assertions become propositions

A Shared Intelligence `entity_geographic_areas` row MAY create a `located_in` relationship proposition with evidence. It MUST NOT auto-adjudicate the proposition merely because the source row exists.

## Core objects

### `reality.place_kinds`

Governed taxonomy of Place roles such as:

- `physical_site`
- `locality`
- `administrative_area`
- `region`
- `postal_area`
- `country`

The registry is extensible; v1 does not claim this list is exhaustive.

### `reality.place_profiles`

Typed extension of a canonical Place Entity.

Minimum fields:

- `entity_id`
- `place_kind`
- optional country code
- optional centroid latitude/longitude
- coordinate precision
- profile state
- evidence/basis

V1 registration is immutable-by-default: an exact repeat is idempotent; conflicting profile semantics fail closed for a later explicit supersession contract.

### Spatial relationship semantics

V1 registers:

- topology axis `spatial_containment` — acyclic, multiple parents allowed;
- relationship kind `located_in` — any Entity -> Place;
- relationship kind `contained_in` — Place -> Place;
- presence class `spatial_membership`.

Both relationship kinds are structural, transitive, and presence-propagating on the spatial axis.

## Shared Intelligence adapters

### Geographic area admission

`atlas.admit_shared_intelligence_geographic_area_to_reality_service_v1(...)`

- validates the Shared Intelligence geographic area;
- preserves its UUID as the Reality Entity UUID;
- fails on stable-key collision;
- establishes one typed Place profile;
- records only source/admission evidence.

### Geographic assertion proposal

`atlas.propose_shared_intelligence_entity_geography_to_reality_service_v1(...)`

- requires both endpoint Entities already exist canonically in Reality;
- records a `located_in` relationship proposition;
- adds source-backed evidence;
- does not adjudicate it.

## Target Intelligence composition

No Place-specific target operator is required in v1.

Existing universal operators compose correctly:

`topology_path_exists(operating_structure -> endpoint)`

whose endpoint predicate may itself be:

`topology_path_exists(spatial_containment -> desired Place)`

Set membership is expressed with `ANY`, `ALL`, `NOT`, and `AT_LEAST_N` over these predicates.

This keeps geography as Reality and business qualification as Ledger policy.

## Non-goals

This tranche does NOT establish:

- driving routes or travel time;
- geofencing;
- polygon geometry;
- PostGIS dependency;
- automatic city-string matching;
- automatic admission of all legacy geographic data;
- Elm corridor rules;
- prospect ranking;
- contact discovery;
- one universal geographic hierarchy.

## Acceptance cases

The validation suite must prove:

1. canonical Place Entity can receive a Place profile;
2. non-Place Entity cannot receive one;
3. exact profile repeat is idempotent;
4. conflicting profile repeat fails closed;
5. invalid coordinates fail closed;
6. `located_in` participates in spatial topology;
7. `contained_in` composes transitively with `located_in`;
8. a target can prove membership in an ancestor Place through nested topology predicates;
9. missing spatial membership remains UNKNOWN with a topology evidence obligation;
10. Shared Intelligence geographic-area admission preserves UUID and creates no Ledger meaning;
11. Shared Intelligence entity-geography adapter creates an open proposition, not canonical truth;
12. all synthetic fixture state rolls back.
