# ATLAS_PAIRED_OPERATING_PRESENCE_V1

## Purpose

Replace label/address OR-search geography with a canonical, proof-bearing primitive:

> the same normalized operating organization has governed presence in Place Set A and Place Set B.

The primitive is universal. Elm corridor bands are consumers, not part of the contract.

## Inputs

- any canonical Reality entity that can normalize through `operating_structure`, or all canonical operating roots for set search;
- non-empty, bounded arrays of canonical Place entity IDs for side A and side B;
- bounded operating and spatial traversal depths;
- an as-of timestamp.

Side arrays must not contain the same Place entity ID. Callers are responsible for constructing semantically distinct regional sets.

## Proof model

For each side Atlas must prove:

1. the canonical operating root;
2. an operating member of that root (the root itself or a descendant reached through presence-propagating `operating_structure` edges);
3. spatial membership of that operating member in one of the requested Place entities, either directly or through presence-propagating `spatial_containment` ancestry.

Returned proof packets preserve both chains independently:

- operating entity/relationship path;
- spatial entity/relationship path;
- matched Place entity.

Two unrelated organizations cannot satisfy opposite sides together because both side proofs are evaluated under one canonical operating root.

## Epistemic rule

Known proof on both sides => `true`.

If either side lacks an established proof => `unknown`, not `false`, with a precise `resolve_operating_place_presence` obligation for each missing side.

This preserves the Reality/Target rule that missing knowledge is not negative truth.

## Search consequence

A set-level search may return only roots whose paired-presence evaluation is `true`. It must return each root once with both proof packets.

Street-name matches, city text in an address, brand similarity, a franchise relationship, or one company on side A plus a different company on side B cannot satisfy the primitive.

## Non-goals

V1 does not decide:

- whether a proven presence is commercially meaningful enough for a specific offer;
- prospect score;
- contact person;
- outreach authority;
- acquisition/adjudication of missing organization or spatial relationships.

Those are separate layers.