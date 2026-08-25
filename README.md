# noel-core-db

Executable database custody for the shared `noel-core` Supabase project.

This repository will own the canonical migration history, database tests, schema ownership boundaries, and generated database types for the physical Supabase project used by Noel, Atlas, and Write Now.

Planned schema ownership:

- `core` — Noel textual/manuscript evidence engine
- `atlas` — Atlas operational system
- `wnph` — Write Now publishing custody
- `wnph_api` — governed Write Now application surface

Application repositories must not become competing migration authorities for the shared Supabase project.

Current phase: custody bootstrap only. Existing Atlas migration history has not yet been moved or re-adjudicated into this repository.
