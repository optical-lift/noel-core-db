# Atlas Governed Subject Validation Preflight — 2026-09-28

Status: **dependency/schema preflight passed; isolated execution still required**

Source checkpoint:

`governed-subject-observation-applicability-v1`

Validation branch:

`validation/governed-subject-observation-applicability-v1`

## Purpose

This receipt records the non-mutating preflight performed before executing the governed-subject observation/applicability migrations and rollback proofs.

It does **not** claim that the migrations or tests have executed successfully.

The source tranche itself requires execution in an isolated database harness. Production must not be used as an ad-hoc substitute merely because the proofs end in `rollback`.

## Source under test

Migrations:

- `supabase/migrations/20260928201500_governed_subject_observation_applicability_v1.sql`
- `supabase/migrations/20260928202000_tighten_governed_subject_membrane_privileges_v1.sql`

Rollback proofs:

- `supabase/tests/20260928_governed_subject_observation_applicability_v1.sql`
- `supabase/tests/20260928_governed_subject_correction_supersession_v1.sql`
- `supabase/tests/20260928_elm_grounds_governed_subject_fixture_v1.sql`

## Production read-only dependency preflight

The current production schema was inspected read-only to verify that the proposed migrations target source structures that actually exist.

Required tables are present:

- `reality.entities`
- `reality.resources`
- `atlas.organizations`
- `atlas.organization_responsibilities`
- `atlas.organization_responsibility_scopes`

The columns used by the migrations/tests are present with compatible types, including:

- Reality entity identity and kind/display fields;
- resource ownership, hierarchy, kind/state, reservation and capacity fields;
- Organization identity/status;
- Responsibility identity/kind/status;
- Responsibility scope kind/id/relation coordinates.

Defaults required by the rollback fixtures are also present:

- new Reality Entities default to canonical identity state;
- new Organizations default active;
- new institutional Responsibilities default active;
- new resources default active.

The proposed new source objects are **not already present** in production:

- `reality.resource_observations` — absent;
- `atlas.organization_responsibility_resource_applicability` — absent;
- observation writer/resolver v1 — absent;
- applicability admission/resolver v1 — absent.

Therefore the tranche is not accidentally duplicating an already-released production membrane.

## Live Elm compatibility preflight

The concrete live domain already contains the identities the proof architecture expects:

```text
canonical Elm Farm Reality business
└─ active Elm Farm Site resource
   └─ active Grounds resource
```

The institutional side independently contains:

```text
active Elm Farm Organization
└─ active grounds_readiness Responsibility
   └─ organization-unit Responsibility scope
```

The current Responsibility structure has exactly one current carrier for `grounds_readiness`, through the `operations_steward` position.

This is important because the source tranche deliberately does **not** derive a Person carrier. The existing institutional Responsibility resolver remains the source for:

```text
who currently carries grounds_readiness?
```

while the new tranche supplies only:

```text
what is the current admitted Grounds observation?
```

and:

```text
does this exact grounds_readiness Responsibility scope apply to this exact Grounds subject for this exact operation?
```

The three questions remain independent.

## SQL contract review

The migration preserves the intended source boundaries:

### Resource observation

- append-only table keyed to exact `reality.resources.id`;
- explicit `observed_at` distinct from `recorded_at`;
- idempotent admission with semantic fingerprint;
- conflicting idempotency reuse fails closed;
- canonical readback occurs before an admission receipt is returned;
- latest read accepts independent observed/recorded as-of bounds;
- no Task/Work/readiness mutation occurs in the writer.

### Responsibility → resource applicability

- exact `organization_responsibility_scopes.id` is the institutional source anchor;
- exact resource and exact operation are explicit;
- effective intervals are first-class;
- admission requires active Organization, Responsibility, and resource at admission time;
- concurrent admissions for the same semantic relation are serialized with an advisory transaction lock;
- overlapping effective intervals fail closed;
- missing applicability resolves as `indeterminate`, not false/prohibited;
- the resolver reports applicability interval state only; current Person carriage remains a separate relation.

### Privilege tightening

The second migration removes direct `service_role` INSERT permission from both new canonical source tables while retaining governed read access. Canonical writes therefore remain behind the two admission membranes.

## Rollback-proof review

The generic proof covers:

- observation admission and replay;
- conflicting replay rejection;
- exact-resource isolation;
- applicability admission and replay;
- overlap rejection;
- current/historical/indeterminate applicability states;
- no legacy Task mutation.

The correction/supersession proof preserves historical facts while allowing later source evidence or later effective intervals to become current.

The Elm fixture preserves the critical identity distinction:

```text
institutional Elm operating scope
!=
physical Grounds resource
```

and joins them only through explicit applicability.

It then proves the intended source chronology:

```text
stale Grounds observation
→ fresh Grounds observation
→ latest read advances
→ historical as-of still returns stale observation
```

## Environment boundary reached

This validation environment has no local PostgreSQL/Supabase runtime and no existing Supabase development branch.

Creating a Supabase development branch is a separate billable-resource action requiring explicit cost/organization confirmation. Production execution was deliberately not used as a substitute because the source checkpoint explicitly forbids ad-hoc production testing.

Therefore the honest validation state is:

```text
source law reviewed
+ production dependencies verified read-only
+ live Elm semantic seam verified read-only
+ test coverage reviewed
≠
isolated migration/test execution passed
```

## Exact reopen action

Do not redesign the source membrane when execution resumes.

Run, in an isolated PostgreSQL/Supabase harness based on the current production migration set:

1. both migration files in order;
2. `20260928_governed_subject_observation_applicability_v1.sql` test;
3. `20260928_governed_subject_correction_supersession_v1.sql` test;
4. `20260928_elm_grounds_governed_subject_fixture_v1.sql` test;
5. privilege checks confirming authenticated/anon cannot directly read/write the tables and `service_role` cannot directly INSERT;
6. schema/security advisors if the harness supports them.

Only after all of those pass should Atlas application adapters be promoted from design to implementation against these resolver envelopes.

## Governing conclusion

No architectural incompatibility was found in the preflight.

The tranche is **ready for isolated execution**, not yet admitted as released source infrastructure.
