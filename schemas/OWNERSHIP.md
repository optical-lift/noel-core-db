# Shared Supabase Schema Ownership

Physical project: `noel-core`

This repository owns the executable migration history for the physical Supabase project. Product schemas remain logically separate even though they share one project.

## Current schema owners

| Schema | Logical owner | Purpose |
| --- | --- | --- |
| `core` | Noel | canonical textual/manuscript evidence engine and related research infrastructure |
| `atlas` | Atlas | operational management system |
| `wnph` | Write Now Publishing House | publication custody, creator/corpus/work/recovery/publication state |
| `wnph_api` | Write Now Publishing House | deliberately exposed views/RPCs for application access |
| `public` | legacy/shared compatibility | older project surfaces requiring explicit adjudication before reuse |

## Hard rules

1. One physical Supabase project has one executable migration authority: this repository.
2. Product repositories may propose database requirements but must not independently become authoritative migration ledgers.
3. Cross-schema dependencies must be explicit, minimal, and documented.
4. `wnph` must not require Noel-specific manuscript structures for ordinary publishing records.
5. Write Now may reference governed/frozen Noel evidence through stable bridges; it must not consume provisional research as publication truth.
6. Existing Atlas migrations remain historical/executable in `farm-atlas` until a separate parity-proven custody cutover is completed. This bootstrap does not silently move or invalidate them.
7. The `public` schema is not a default shared namespace. New product tables belong in their owning schema.

## Future splitability

Logical ownership must remain strong enough that any product schema can later move to its own physical project without untangling unrelated tables. Shared physical hosting is a cost decision, not permission to merge product semantics.
