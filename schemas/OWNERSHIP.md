# Shared Supabase Schema Ownership

Physical project: `noel-core`

This repository owns the executable migration history for the physical Supabase project after the inherited-history fence defined in `custody/production-baseline-v1.json`. Product schemas remain logically separate even though they share one project.

## Current schema owners

| Schema | Logical owner | Purpose |
| --- | --- | --- |
| `core` | Noel | canonical textual/manuscript evidence engine and related research infrastructure |
| `atlas` | Atlas | operational management system |
| `wnph` | Write Now Publishing House | private canonical publication custody, creator/corpus/work/recovery/publication state |
| `wnph_api` | Write Now Publishing House | deliberately exposed views/RPCs for application access; closed until individual surfaces are explicitly granted |
| `public` | legacy/shared compatibility | older project surfaces requiring explicit adjudication before reuse |

`wnph` and `wnph_api` were absent at the production cutover and were first created post-fence by `wnph_product_schema_membrane_v1`. Both schemas are owned by `postgres`; `anon`, `authenticated`, and `service_role` have no schema `USAGE` or `CREATE` privilege by default. Future application access must be granted deliberately through `wnph_api`; canonical `wnph` custody is not an application query surface.

## Inherited namespaces

The production database also contains older specialized schemas such as `backup`, `draft`, `fundraising`, `instrument`, `intelligence`, `lab`, `local_intel`, `practice`, `reader`, `registry`, `snail`, `snail_read`, `staging`, and `titus`. They are inherited database history at the fence; this document does not silently reassign their semantics to a new product. Reuse, retirement, or cross-product dependency requires explicit adjudication in a post-fence migration.

`cron` and `net` are extension-managed namespaces observed at the fence and are not product ownership targets.

## Hard rules

1. One physical Supabase project has one post-fence executable migration authority: this repository.
2. Product repositories may propose database requirements and retain pre-fence migration provenance, but must not independently become authoritative post-fence migration ledgers.
3. Cross-schema dependencies must be explicit, minimal, and documented.
4. `wnph` must not require Noel-specific manuscript structures for ordinary publishing records.
5. Write Now may reference governed/frozen Noel evidence through stable bridges; it must not consume provisional research as publication truth.
6. Production migration history through `20260825203448` is inherited and frozen. It is not recopied here, renamed, or invalidated by the cutover.
7. The `public` schema is not a default shared namespace. New product tables belong in their owning schema.
8. `wnph` remains private canonical custody. Application roles do not receive direct schema access.
9. `wnph_api` is deny-by-default. Each future view/function and role grant requires an explicit migration.
10. A Write Now application surface may read or mutate `wnph` only through a governed `wnph_api` object or an explicitly documented server-side bridge; direct product-app coupling to canonical tables is forbidden.

## Future splitability

Logical ownership must remain strong enough that any product schema can later move to its own physical project without untangling unrelated tables. Shared physical hosting is a cost decision, not permission to merge product semantics.
