# Shared Intelligence Universal Acquisition v1

## Purpose

Complete the write-side half of the one-copy Shared Intelligence model.

Shared Directory v1 established universal consumption:

```text
canonical Shared Intelligence entity
+ requesting Atlas Ledger overlay
= contextual directory entry
```

This package establishes the matching acquisition rule:

```text
request / research context
→ universal Shared Intelligence identity resolution
→ reuse canonical entity when supported
→ establish contextual relevance separately
→ apply source-backed evidence to canonical entity
```

A Local context remains useful as provenance for why research occurred. It is no longer an identity namespace.

## Governing rule

`local_intel.entities.local_context_id` is a compatibility/discovery-origin pointer only.

It must not decide whether another context may:

- identify the same canonical entity;
- attach source-backed evidence to it;
- recommend it as an ingestion-candidate match;
- approve it as the canonical match;
- record that the canonical entity is relevant/known in another context.

Contextual relevance is represented by `local_intel.entity_context_memberships`.

## Transition

This package deliberately preserves historical columns, candidate uniqueness, search provenance and existing writer names so current Elm discovery execution continues to work.

It changes their semantics:

- `search_queries.local_context_id` = requesting/research context;
- `entity_ingestion_candidates.local_context_id` = intake/research context;
- entity IDs referenced by those records = universal canonical Shared Intelligence identities;
- `entity_context_memberships` = nonexclusive contextual relevance.

## Guard correction

The historical guard functions retain their names for trigger compatibility but stop enforcing legacy identity ownership:

- `enforce_search_entity_context_v1`
- `enforce_search_evidence_context_v1`
- `enforce_ingestion_candidate_local_context_v1`

They still fail closed on missing search contexts or nonexistent entity IDs.

They no longer require `entities.local_context_id = requesting local_context_id`.

## Membership consequence

When a search/research context lawfully reuses a canonical entity, the context receives or refreshes an active `known_in` membership.

Membership establishment occurs for:

- discovery evidence bound to a canonical subject;
- discovery evidence naming a canonical organization;
- canonical search findings;
- approved/matched ingestion candidates.

The canonical entity UUID and legacy discovery-origin pointer remain unchanged.

## Discovery intake

`ingest_search_discovery_evidence_v1` remains the compatibility entry point used by the existing Elm discovery executor.

It now accepts any existing canonical Shared Intelligence entity as `entity_id` or `organization_entity_id`, regardless of legacy origin context.

When no canonical entity is supplied, the existing ingestion candidate + universal Resolver path remains in place.

The Resolver recommendation views already search the entire canonical entity corpus. Human adjudication remains required where the existing resolver requires it. This package does not introduce automatic merge.

## Non-goals

This package does not:

- globally unique `entities.stable_key`;
- rewrite historical UUIDs;
- auto-merge ambiguous duplicates;
- remove `local_context_id`;
- create Atlas Ledger relationships merely because research found an entity;
- move private notes/campaigns into Shared Intelligence;
- authorize communication.

## Acceptance proof

Two separate Local contexts exist in a rollback-only clone fixture.

Context A owns the legacy discovery-origin pointer for two canonical entities.

Context B then:

1. starts a search;
2. applies source-backed email evidence directly to a canonical Context-A entity;
3. receives Context-B membership for that same entity;
4. leaves the entity's legacy pointer unchanged;
5. creates no duplicate entity;
6. stages an ingestion candidate whose global Resolver recommendation points to another canonical Context-A entity;
7. approves that match through the existing adjudication path;
8. reuses the same canonical UUID and establishes Context-B membership.

This proves one-copy identity across multiple research contexts while preserving contextual provenance.
