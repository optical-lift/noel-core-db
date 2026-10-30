# Ledger reciprocal root + original institutional Work — RELEASE PACKAGE ONLY

This directory contains no alternate Work architecture. Its function bodies, fixture, and postconditions preserve the exact signed-clone source in the tested order from protected scratch run #41141773149, **which PASSED** with separate local signed GoTrue/PostgREST sessions. The release SQL deliberately **joins P0 and P1 into one transaction**, removing only the first `COMMIT;` and second `BEGIN;` at their junction. Noel's production release runner must insert its custody receipt before the **only** terminal `COMMIT;`, so a two-transaction concatenation is unsafe.

- `candidate.sql`: source P0 `candidates/atlas-ledger-work-authority-20261030/root-scoped-peer-source-candidate.sql` at `3baf2f4a909e35d9eb2d56f663f3c6aefc52a7f7`, immediately followed by P1 `candidates/atlas-ledger-work-intake-20261030/candidate.sql` at `0f881f1e15dea69018aa951ef17ce362019408b8`.
- `postconditions.sql`: matching P0 then P1 postcondition files in that order.
- `fixture.sql`: `candidates/atlas_work_self_assignment_native_v1/fixture.sql` followed by `validation/fixtures/atlas_ledger_reciprocal_root_signed_clone_20261030.sql`; all synthetic DML, **never production data**.

Signed evidence: https://github.com/optical-lift/noel-core-db/actions/runs/41141773149. Real signed employee, reciprocal Ledger-root, outsider, anonymous, same-token ended-authority denials; one original unassigned Work, private source readback, inbox and root review, no duplicate Person/Principal. Candidate-introduced Atlas lint errors: 0, inherited baseline: 14.

This source package is a required input for the existing **Governed Migration Source Generation** issue workflow. Do not submit it directly to production. Generate a single CLI-versioned `atlas_ledger_reciprocal_root_work_intake_v1` migration under the protected generator, open a new migration PR and pass full disposable clone + domain checks. An explicit owner-approved protected release of the exact version is separately required; Atlas UI deployment and independently signed live smoke remain later gates.
