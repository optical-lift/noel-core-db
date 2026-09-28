# Atlas Governed Subject PostgreSQL Engine Validation — 2026-09-28

**Status:** isolated PostgreSQL execution passed; branch-only; not released

Validation branch:

`validation/governed-subject-observation-applicability-v1`

Source checkpoint:

`governed-subject-observation-applicability-v1`

## Purpose

This receipt closes the zero-cost engine-validation gate for the governed resource-observation and Responsibility→resource-applicability source tranche without creating a paid Supabase development branch and without mutating production.

The validation used a real PostgreSQL engine, not SQLite and not only a behavioral model.

## Zero-cost PostgreSQL harness

The engine was Electric SQL PGlite 0.5.8, downloaded from Electric's own successful public GitHub Actions build artifact:

- repository: `electric-sql/pglite`;
- workflow run: `32999547423`;
- workflow head: `ae182ff8bd5ba4acb887d6c925d607a1498aa0b5`;
- artifact: `pglite-package-node-v22.x`;
- artifact ID: `9618325452`.

The resulting local engine reported PostgreSQL 18.3 / PGlite 0.5.8.

The harness ran entirely in the current isolated session. No Supabase branch, paid cloud database, production schema mutation, PR, or GitHub Actions run was created.

## Dependency shape

Before engine execution, production was inspected read-only and the exact source dependencies used by the tranche were verified:

- `reality.entities`;
- `reality.resources`;
- `atlas.organizations`;
- `atlas.organization_responsibilities`;
- `atlas.organization_responsibility_scopes`;
- the required columns, defaults, and state values used by the rollback fixtures.

A minimal local dependency schema matching that verified shape was then created in the PGlite database.

This was not represented as a complete production clone. It was an isolated PostgreSQL execution against the verified dependency surface of this tranche.

## PostgreSQL capability smoke test

Before Atlas SQL was loaded, the harness verified that the engine supports every PostgreSQL primitive used by these migrations:

- PL/pgSQL `DO` blocks;
- `gen_random_uuid()`;
- `tstzrange` overlap semantics;
- `hashtextextended()`;
- transaction-scoped advisory locks;
- role creation and role privilege inspection.

All passed.

## First execution finding: proof bug, not source-migration bug

Both migrations compiled and applied successfully on the first run.

The first generic rollback proof then exposed a test-time error:

```text
record_resource_observation_service_v1
→ recorded_at = clock_timestamp()

same transaction
→ resolver called with recorded_as_of = now()
```

PostgreSQL `now()` is transaction-start time. Therefore an observation admitted later in the same transaction correctly has:

```text
recorded_at > now()
```

and is correctly excluded by a resolver asked to read only facts recorded by that earlier instant.

The failing proof was therefore contradicting the source contract's deliberate distinction:

```text
observed_at != recorded_at
```

The source writer/resolver were not changed.

The affected rollback proofs were corrected so immediate post-write reads use:

```text
observed_as_of = the intended observed-world coordinate
recorded_as_of = clock_timestamp()
```

Historical `observed_as_of` remains explicit and independent.

Corrected files:

- `supabase/tests/20260928_governed_subject_observation_applicability_v1.sql`;
- `supabase/tests/20260928_elm_grounds_governed_subject_fixture_v1.sql`.

The correction/supersession proof already supplied a later explicit recorded-as-of coordinate and required no change.

## Final execution result

After that correction, the isolated PostgreSQL run passed all of the following:

1. verified dependency schema creation;
2. `20260928201500_governed_subject_observation_applicability_v1.sql` migration;
3. `20260928202000_tighten_governed_subject_membrane_privileges_v1.sql` migration;
4. generic observation/applicability rollback proof;
5. correction/supersession rollback proof;
6. Elm Grounds rollback fixture;
7. role/privilege assertions;
8. rollback-isolation assertions.

Final harness state:

```text
all_passed: true
```

## Privilege assertions passed

The real PostgreSQL catalog established:

- `service_role` may SELECT `reality.resource_observations`;
- `service_role` may not directly INSERT `reality.resource_observations` after privilege tightening;
- `service_role` may SELECT `atlas.organization_responsibility_resource_applicability`;
- `service_role` may not directly INSERT the applicability table after privilege tightening;
- `anon` may not SELECT the observation source table;
- `authenticated` may not SELECT the observation source table;
- `service_role` may execute the governed observation writer;
- `anon` and `authenticated` may not execute that writer.

Thus canonical writes remain behind the admitted service membranes rather than direct-table INSERT authority.

## Rollback isolation passed

After all three transaction-wrapped proofs completed, the isolated database contained zero proof-fixture rows in:

- Reality Entities;
- Reality resources;
- Organizations;
- resource observations;
- Responsibility/resource applicability;
- compatibility Tasks.

The tests therefore exercised source behavior without leaking fixture truth into subsequent proofs.

## Source-law conclusions now supported by real PostgreSQL execution

The tranche has engine-level support for:

- append-only exact-subject observations;
- independent observed and recorded time coordinates;
- idempotent source admission;
- conflicting idempotency reuse failure;
- canonical post-write readback;
- exact-resource isolation;
- latest and historical as-of observation reads;
- exact Responsibility-scope/resource/operation applicability;
- half-open effective intervals;
- overlap rejection;
- current / established-not-current / indeterminate applicability distinction;
- service-membrane-only writes;
- no Task manufacturing as a side effect.

## Bounded correction limitation

One intentionally unfinished source operation remains.

Observation correction is already additive:

```text
observation A
→ later observation B
→ present read selects B
→ historical observed-as-of still selects A
```

Applicability replacement is also proven when the first interval already has an admitted end and a second adjacent interval begins at that boundary.

What does **not** yet exist is a governed writer for the unexpected correction of an already-open-ended applicability row, for example:

```text
existing [t0, infinity) applicability
→ later determination that it ended at t1
→ close historical interval lawfully
→ admit replacement or absence from t1 onward
```

The current admission writer correctly rejects an overlapping replacement rather than silently rewriting the open interval.

This limitation does not block the first Elm observation-acquisition proof, because that proof needs only one current applicability relation. It must be addressed before Atlas needs retroactive correction/closure of an already-open-ended applicability fact.

## Application gate

The database-side source tranche has now crossed the engine-validation boundary required by the Atlas governed-reality closeout.

The next work is application-side and should proceed directly from the already-frozen source-backed proof plan:

1. typed adapter for `reality.resolve_resource_observation_latest_v1`;
2. typed adapter for `atlas.resolve_organization_responsibility_resource_applicability_current_v1`;
3. reuse current institutional Responsibility adapter;
4. implement the narrow observation-acquisition relation/policy;
5. prove `missing observation → supported encounter → source writeback → re-resolution → natural silence` without synthetic mowing law or Task completion state.

No production release is implied by this receipt.
