# Atlas Teaching Academic Kernel v1 candidate package

Status: **source-complete, inert, not migration-identified, not clone-validated**.

This directory is deliberately outside `supabase/migrations/` and `validation/`. Nothing here is executable by the production release lane.

## Files

- `candidate.sql` — base Gate B schema and APIs.
- `hardening.sql` — implementation hardening discovered during source review. It replaces the Course-create function's activation ordering with Gate A fields that actually exist and adds database-level terminal/identity guards for Course, Offering, and Enrollment.
- `fixture.sql` — DML-only production-shaped identities/Ledgers used by the future clone harness.
- `postconditions.sql` — behavioral proof of the Gate B contract.

## Promotion rule

Do **not** copy `candidate.sql` alone into a migration.

When a legitimate migration identity is generated using the repository-pinned Supabase CLI, the canonical migration bytes must be constructed in this order:

```text
candidate.sql
hardening.sql
```

The duplicate `begin`/`commit` boundaries may remain as two consecutive transactions or be normalized only before validation; whichever byte form becomes the governed migration must then remain immutable through clone validation, PR review, merge, and release.

The future governed package must then use the same generated version for:

```text
supabase/migrations/<version>_atlas_teaching_academic_kernel_v1.sql
validation/fixtures/<version>_atlas_teaching_academic_kernel_v1.sql
validation/migrations/<version>_atlas_teaching_academic_kernel_v1.sql
```

## Required gates before merge

1. Generate the migration with `supabase migration new atlas_teaching_academic_kernel_v1` using the repository-pinned CLI.
2. Promote the candidate bytes and matching fixture/postconditions.
3. Run Production Schema Clone Validation against an immutable candidate SHA.
4. Fix only evidence-backed defects and rerun until green.
5. Require zero candidate-introduced Atlas lint errors.
6. Open PR only on the exact clone-green SHA.
7. Production release remains a later, separately governed action.

## Current proof target

The proof must establish:

```text
active Teaching v1
  -> Course
  -> immutable Course Version
  -> exact-version Course Offering
  -> Enrollment of an existing Atlas Person
  -> learner self-read
```

and must prove that Enrollment creates no Organization membership, Principal, Principal/Ledger authority, commercial offering, auth identity, or parallel user truth.
