# noel-core-db

Executable database custody for the shared `noel-core` Supabase project.

This repository owns canonical database migrations, database custody tests, schema ownership boundaries, and generated database contracts for the physical Supabase project used by Noel, Atlas, and Write Now.

The inherited production history is now fenced in `custody/production-baseline-v1.json`. Everything in the production migration ledger through version `20260825203448` is frozen inherited history; it is not recopied into this repository. Canonical migrations after that fence originate here.

Planned schema ownership:

- `core` — Noel textual/manuscript evidence engine
- `atlas` — Atlas operational system
- `wnph` — Write Now publishing custody
- `wnph_api` — governed Write Now application surface

Application repositories may retain pre-fence migration files as provenance and may propose new database requirements, but they must not become competing post-fence migration authorities for the shared Supabase project.

Post-fence Atlas migrations use the `atlas_` logical-owner prefix, including incident repairs whose live migration identity is normalized to the canonical source filename before custody verification.

See `custody/PRODUCTION_BASELINE.md` for the cutover contract and `schemas/OWNERSHIP.md` for logical schema boundaries.
