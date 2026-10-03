# ATLAS_REALITY_ORGANIZATION_TOPOLOGY_V1

## Purpose

Give Reality a universal, proof-bearing operating-organization topology so applications can ask whether two units, branches, locations, departments, clinics, or schools belong to the same operating organization without inferring identity from names, addresses, brands, or customer-specific search rules.

This contract is an identity/topology substrate. It does not decide whether an organization is a good Elm prospect, whether a franchise should be contacted, or whether a researched relationship is true. Those remain separate policy and adjudication questions.

## Core distinction

`same operating organization` is narrower than `corporately related`, `uses the same brand`, `belongs to the same chapter network`, or `is a franchise of`.

V1 therefore places only relationships that support direct operating containment on the `operating_structure` topology axis:

- `operating_unit_of`
- `operating_unit_parent`
- `location_of`
- `branch_of`
- `department_of`
- `clinic_of`
- `school_of`

The following are deliberately **not** operating-structure relationships in v1:

- `subsidiary_of` — corporate control is not identical operating structure.
- `chapter_of` — network/governance affiliation may preserve local autonomy.
- `franchise_of` — franchise identity does not imply common operating control.
- `uses_brand` / `brand_used_by` — Shared Intelligence explicitly says these do not imply parentage or ownership.

Future contracts may register separate topology axes for those relationships.

## Canonical operating axis

`operating_structure`

- acyclic
- one simultaneous parent entity per child
- structural
- transitive
- presence-propagating

Multiple source relationship kinds may point the same child at the same parent. That is multiple evidence/semantics for one parent, not multiple-parent ambiguity. A different simultaneous parent fails closed.

Presence class:

`direct_operating_presence`

This means the child is a direct operating component of the parent for topology traversal. It does not imply legal-entity equality, ownership percentage, or communication authority.

## Internal Atlas organization units

`atlas.organization_units` remains the governed legacy carrier during cutover. An active unit may be admitted to Reality as:

- the same unit UUID,
- `entity_kind = organization_unit`,
- a globally scoped Reality stable key,
- an explicit `compatibility.legacy_bindings` mapping.

The parent Organization is **never** inferred by copying `atlas.organizations.id`. The adapter must resolve the existing canonical Reality root through `atlas.reality_entity_for_legacy_organization_internal_v1`.

For a top-level unit, the canonical relationship is:

`Organization Unit --operating_unit_of--> canonical Reality organization/business`

For a nested unit:

`child Organization Unit --operating_unit_parent--> parent Organization Unit`

The adapter may adjudicate these relationships because `atlas.organization_units` is already governed canonical internal truth. Even then, it must pass through the Reality relationship proposition/evidence/adjudication membrane.

## Shared Intelligence organization structure

Shared Intelligence remains an evidence source, not canonical Reality authority.

A Shared Intelligence relationship may be proposed into Reality only when:

- its kind is in the v1 direct-operating allowlist,
- it is current,
- `truth_state = accepted_current`,
- `conflict_state = none`,
- both endpoint identities already exist as canonical Reality entities.

The adapter creates an OPEN Reality relationship proposition with source evidence. It never auto-adjudicates the external relationship.

## Search consequence

This contract makes branch/root normalization executable. A later paired-presence search may:

1. resolve every candidate unit/location to its `operating_structure` root;
2. prove spatial membership for each operating descendant using `spatial_containment`;
3. require proofs in side A and side B for the **same root**;
4. return the root once, with separate branch/location/spatial proof paths.

Text labels, street names, brand similarity, and unrelated entities on opposite sides cannot satisfy that predicate.

## Non-goals

V1 does not:

- auto-admit all Shared Intelligence entities;
- auto-promote Shared Intelligence hierarchy claims;
- merge legal entities;
- treat subsidiaries/franchises/chapters/brands as one operating organization;
- authorize outreach;
- rank prospects;
- encode Elm-specific geography or score rules.
