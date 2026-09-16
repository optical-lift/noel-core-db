# Shared Supabase Schema Ownership

Physical project: `noel-core`

This repository owns the executable migration history for the physical Supabase project after the inherited-history fence defined in `custody/production-baseline-v1.json`. Product schemas remain logically separate even though they share one project.

## Current schema owners

| Schema | Logical owner | Purpose |
| --- | --- | --- |
| `core` | Noel | canonical textual/manuscript evidence engine and related research infrastructure |
| `mark` | Noel | private culture-agnostic physical mark evidence custody: source objects, surfaces, captures, regions, components, topology/junctions, anonymous sequence position and source-truth freeze state |
| `atlas` | Atlas | operational management system |
| `local_intel` | Shared Intelligence | canonical external-world entities, public-source contacts and relationships, identity evidence, discovery, resolution, enrichment, and contextual relevance without contextual identity ownership |
| `wnph` | Write Now Publishing House | private canonical publication custody, creator/corpus/work/recovery/publication state |
| `wnph_api` | Write Now Publishing House | deliberately exposed views/RPCs for application access; closed until individual surfaces are explicitly granted |
| `reporting` | Reporting | private source-custodied newsroom memory for sources, passages, entities, claims, events, money, actions, votes, quotes and continuing story topics |
| `public` | legacy/shared compatibility | older project surfaces requiring explicit adjudication before reuse |

`mark` is Noel-owned physical evidence custody, introduced post-cutover by `core_mark_physical_evidence_kernel_v1`. It is deliberately more general than `core.manuscript_registry`: a sign-bearing object may be a manuscript leaf, tablet, bone, seal, textile, tally, diagram or another durable physical carrier without requiring a language, Unicode identity, canonical passage, or inherited character boundary. `mark` is private by default; `public`, `anon`, `authenticated`, and `service_role` receive no direct schema access in v1. Analytical engines may reference frozen `mark` evidence through explicit cross-schema contracts, but their predictions and interpretations never mutate physical source truth.

`local_intel` is Shared Intelligence custody. Its external-world entity graph is shared infrastructure rather than an Atlas tenant directory: a real-world person, organization/business, place, or other supported referent is represented canonically and may be relevant to many product or organizational contexts without being cloned for each context. Context-specific commentary, transactions, correspondence, preferences, work, and other private operational reality remain in the owning product/domain and reference Shared Intelligence only through explicit governed bridges. The inherited `local_intel.entities.local_context_id` column remains temporarily as a compatibility/discovery-origin pointer; it is not canonical identity ownership. See `architecture/SHARED_INTELLIGENCE_IDENTITY_CUSTODY.md`.

`wnph` and `wnph_api` were absent at the production cutover and were first created post-fence by `wnph_product_schema_membrane_v1`. Both schemas are owned by `postgres`; `anon`, `authenticated`, and `service_role` have no schema `USAGE` or `CREATE` privilege by default. Future application access must be granted deliberately through `wnph_api`; canonical `wnph` custody is not an application query surface.

`reporting` was established post-cutover as a private newsroom schema. The frozen cutover baseline is not rewritten to pretend Reporting existed then; current custody explicitly recognizes the `reporting` migration-owner prefix. `public`, `anon`, and `authenticated` receive no Reporting schema access in v1, and unpublished interviews, transcripts, notes or other reporter-private source material must never be committed to this public repository.

## Inherited namespaces

The production database also contains older specialized schemas such as `backup`, `draft`, `fundraising`, `instrument`, `intelligence`, `lab`, `practice`, `reader`, `registry`, `snail`, `snail_read`, `staging`, and `titus`. They are inherited database history at the fence; this document does not silently reassign their semantics to a new product. Reuse, retirement, or cross-product dependency requires explicit adjudication in a post-fence migration.

`cron` and `net` are extension-managed namespaces observed at the fence and are not product ownership targets.

## Hard rules

1. One physical Supabase project has one post-fence executable migration authority: this repository.
2. Product repositories may propose database requirements and retain pre-fence migration provenance, but must not independently become authoritative post-fence migration ledgers.
3. Cross-schema dependencies must be explicit, minimal, and documented.
4. Shared Intelligence canonical entities are not owned by a Local/product/organization context. Contexts may establish relevance, discovery, curation, or operational relationships to a canonical entity but must not fork that external-world identity for contextual use.
5. Private or organization-specific observations do not become universal merely because they refer to a Shared Intelligence entity; their original product/domain retains custody.
6. `wnph` must not require Noel-specific manuscript structures for ordinary publishing records.
7. Write Now may reference governed/frozen Noel evidence through stable bridges; it must not consume provisional research as publication truth.
8. Production migration history through `20260825203448` is inherited and frozen. It is not recopied here, renamed, or invalidated by the cutover.
9. The `public` schema is not a default shared namespace. New product tables belong in their owning schema.
10. `wnph` remains private canonical custody. Application roles do not receive direct schema access.
11. `wnph_api` is deny-by-default. Each future view/function and role grant requires an explicit migration.
12. A Write Now application surface may read or mutate `wnph` only through a governed `wnph_api` object or an explicitly documented server-side bridge; direct product-app coupling to canonical tables is forbidden.
13. `reporting` remains private newsroom custody. Public application access, if ever needed, must be introduced through a separately governed surface rather than direct grants to canonical Reporting tables.
14. `mark` physical source truth is downstream-immutable after freeze. Corrections create new physical records plus explicit supersession lineage; recurrence engines, recovery predictions, linguistic readings, and scholarship may reference but must never rewrite frozen observations.

## Future splitability

Logical ownership must remain strong enough that any product schema can later move to its own physical project without untangling unrelated tables. Shared physical hosting is a cost decision, not permission to merge product semantics.
