# Atlas Event Work — exact executed source-custody recovery, 2026-10-25

This is **historical source reconstruction only** for four structural Atlas Event Work migrations that already executed in the shared production database. No SQL from these files should be run again.

## Source-of-record and proof

A read-only query to `supabase_migrations.schema_migrations` in `zirqkouammpwxlqfbsvf` retrieved each migration's sole original `statements[1]` body. These exact body strings were written without modification into files with their original version and name in `supabase/migrations`.

An **independent read** of `public.shared_db_custody_release_packet_v1()` reported each live executed-statement Git blob SHA-1. For each file, an independent GitHub `fetch_file` returned the *same* blob SHA-1:

| Version | Canonical migration name | Exact live and Git blob SHA-1 |
| --- | --- | --- |
| 20261025210219 | atlas_event_shared_work_canonicalization_v1 | b7f1fe2f559882ac685e9dbac2a979526e44fea6 |
| 20261025210452 | atlas_event_work_responsibility_scope_v1 | 9546090b6b79d36176e0798fa8805793b3f37990 |
| 20261025211045 | atlas_existing_event_work_connected_guard_v1 | d5392ff6bfdff7991e52575811b9e64318ca2ffc |
| 20261025211116 | atlas_event_existing_work_connected_assignment_v1 | 63195f1f0eace800dc1e3a2eeb61ea9cde04ac66 |

All four are `atlas_` structural changes (tables, functions, triggers/grants), not research data, protected customer records, source-document extracts, or hardcoded Elm/Optical Lift testimony. The `INSERT` forms in two definitions are inside functions; **recovering their source text does not run them**.

## Adjudication and boundaries

- `custody/post-fence-migration-recoveries-v58.json` is an immutable retrospective registry inheriting v57. It acknowledges that the original executions reached production without Noel's source gate. It does **not** claim that their author originally followed that gate.
- `scripts/check-custody.sh` seals the registry Git blob and recognizes four new exact recovered source identities; `custody/live-custody-reconciliation-policy-v1.json` loads through v58.
- Never update or spoof `supabase_migrations.schema_migrations`, fabricate an earlier PR, change the recovered SQL text, or invoke a SQL-release workflow for the four already-executed versions.
- Global custody CI must inspect production using its own packet and pass. A local file/Git check alone is not sufficient. Any new active-tail receipt remains blocking.
- Only after global custody CI is green may the **separate**, previously clone-validated Atlas Proper Discovery migration `20261025141943_shared_atlas_proper_foundry_inventory_v1.sql` enter its protected release workflow. The Atlas Workbench UI release is separate again.

This is not a decision that the Event Work functionality is complete or secure in the product; it restores migration history identity, without inventing runtime tests for that distinct build.
