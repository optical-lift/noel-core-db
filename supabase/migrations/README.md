# Migration custody

This directory is the canonical executable migration path for the physical `noel-core` Supabase project **after** the inherited-history fence.

Production history through version `20260825203448` is recorded by `custody/production-baseline-v1.json` and remains frozen inherited history. Those 2,022 migrations are not copied into this directory merely to recreate the past.

Every migration added here must:

1. have a version strictly later than `20260825203448`;
2. carry an explicit owner prefix: `core`, `atlas`, `wnph`, `shared`, or `project`;
3. represent a new canonical database change for the shared physical project;
4. preserve the logical schema ownership rules in `schemas/OWNERSHIP.md`.

Examples:

```text
YYYYMMDDHHMMSS_wnph_creator_corpus_v1.sql
YYYYMMDDHHMMSS_atlas_state_progression_next_cut_v1.sql
YYYYMMDDHHMMSS_shared_cross_schema_bridge_v1.sql
```

Product repositories may retain or repair source custody for migrations inside the inherited fence, but a post-fence production migration must originate here rather than establishing another executable ledger.
