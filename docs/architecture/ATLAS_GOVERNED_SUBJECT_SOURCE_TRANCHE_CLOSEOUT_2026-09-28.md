# Atlas Governed Subject Source Tranche Closeout — 2026-09-28

Status: **closed architecture/source-contract checkpoint; not released**

Branch: `governed-subject-observation-applicability-v1`

## Scope closed

This tranche establishes two source-domain membranes without deploying them:

1. append-only observations about canonical `reality.resources` subjects;
2. governed applicability from one exact institutional Responsibility scope to one exact resource subject for one exact operation.

The branch also contains rollback-only proofs for base admission semantics, correction/supersession, and the concrete Elm Farm Grounds case.

## Admitted source laws

### Resource observation

A resource observation:

- concerns one exact `reality.resources` subject;
- preserves `observed_at` separately from `recorded_at`;
- preserves observer and provenance;
- is admitted idempotently through the source membrane;
- is re-readable from canonical source state before admission returns success;
- does not create Task, Work, readiness, encounter, or execution-authority state.

Later observation evidence does not erase earlier evidence. Current resolution may move forward while historical `as_of` reads retain the earlier answer.

### Responsibility→resource applicability

Applicability:

- references one exact existing `organization_responsibility_scopes` row;
- references one exact canonical resource subject;
- names one exact operation;
- has explicit effective time bounds;
- is admitted idempotently;
- rejects overlapping effective intervals for the same exact relation;
- treats missing applicability as `indeterminate`, not false/prohibited;
- does not create assignment, Work, Task, ownership, or execution authority.

A replacement interval supersedes the prior interval for current resolution without rewriting the prior interval out of history.

## Elm proving case

The concrete fixture preserves these distinct identities:

- Elm institutional Responsibility scope: Elm operating-business organization unit;
- physical subject: canonical `Grounds` resource beneath `Elm Farm Site`.

They are not equal and are joined only by an explicit applicability relation.

The fixture proves:

```text
stale Grounds observation
→ later fresh Grounds observation
→ current source answer moves forward
→ historical answer remains recoverable
```

and:

```text
Elm grounds_readiness Responsibility scope
+
explicit applicability to physical Grounds
+
operation acquire_current_grounds_observation
→ source-backed applicability
```

## Files in this tranche

- `supabase/migrations/20260928201500_governed_subject_observation_applicability_v1.sql`
- `supabase/migrations/20260928202000_tighten_governed_subject_membrane_privileges_v1.sql`
- `supabase/tests/20260928_governed_subject_observation_applicability_v1.sql`
- `supabase/tests/20260928_governed_subject_correction_supersession_v1.sql`
- `supabase/tests/20260928_elm_grounds_governed_subject_fixture_v1.sql`
- `docs/architecture/ATLAS_GOVERNED_SUBJECT_SOURCE_MEMBRANES_V1.md`

## Intentionally not done

This checkpoint does **not** mean:

- the migration was applied anywhere;
- the SQL tests were executed;
- production data changed;
- a PR was opened;
- a deployment occurred;
- Atlas application code may query these tables directly;
- Responsibility itself became attention, Work, assignment, or execution authority.

## Release boundary

The next source-repo step, when this tranche is reopened, is:

1. run the migration and rollback-only proofs in an isolated database harness;
2. inspect failures without changing the source laws above merely to satisfy fixtures;
3. only after the source contract passes isolated validation, decide whether to promote the migration toward a normal review/release path.

Until then this branch is a frozen source-contract checkpoint.
