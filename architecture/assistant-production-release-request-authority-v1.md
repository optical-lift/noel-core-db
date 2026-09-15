# Assistant Production Release Request Authority v1

Status: architecture / operating rule

## Purpose

Record the durable operating rule for assistant-originated production database releases in `noel-core-db`.

The assistant may originate a **release request**. The assistant does **not** gain direct production authority.

The protected production release machinery remains the only authority allowed to decide whether a canonical migration may reach production.

## Authority split

```text
USER AUTHORIZATION
      ↓
ASSISTANT
verify + propose release request
      ↓
GITHUB RELEASE REQUEST ENVELOPE
      ↓
PROTECTED RELEASE MACHINERY
custody + membrane + live-state checks
      ↓
PRODUCTION
```

The actor proposing a release must not be the actor allowed to declare the release lawful.

## Preferred assistant control surface

The assistant-facing control surface is a **GitHub Issue used as a machine-readable production release request**.

The request Issue is only a proposal envelope. It must never contain executable SQL, arbitrary shell commands, migration contents, database credentials, service-role credentials, or any other production secret.

The request identifies only the canonical release target required by the current request workflow, including:

- exact 14-digit `migration_version`;
- `release_lane` (`atlas`, `wnph`, or `shared`);
- exact `production_target`;
- `source_branch`, which must be `main`.

For this repository the production project ref is:

`zirqkouammpwxlqfbsvf`

## Required assistant behavior

When the user authorizes a production release with language such as `release it`, `go ahead`, `keep going`, or an explicit ordered migration list, the assistant should:

1. Re-read current live state rather than relying on an old chat handoff.
2. Confirm the exact migration exists on current `main` and resolves unambiguously to one canonical migration file.
3. Confirm production does not already contain that migration.
4. Confirm required predecessor migrations are live when dependency order is material.
5. Create the governed release-request Issue using the exact canonical migration version, release lane, production target, and `source_branch: main`.
6. Observe the resulting protected release run and verify its result before originating the next dependent release request.
7. Continue sequentially only after the prior release has passed post-release custody verification.
8. Record or surface any refusal faithfully; do not reinterpret a failed membrane check as permission to proceed another way.

If the Issue-based release-request seam cannot be invoked, the assistant must stop at the request boundary and state the missing operation. It must **not** substitute direct Supabase migration application, direct DDL, secret-bearing workflows, alternate service-role paths, or other release bypasses.

## Protected workflow responsibilities

The Issue or assistant must not be trusted as a source of migration bytes.

The protected release machinery independently:

- validates the request schema and exact production target;
- resolves the requested version from `main`;
- requires exactly one canonical migration file for that version;
- retrieves the migration bytes from repository custody, not from Issue prose;
- verifies repository custody;
- verifies the applicable release-lane membrane;
- verifies the production release seam contract;
- verifies live production custody before release;
- applies exactly one canonical migration;
- verifies live production custody after release;
- leaves a durable GitHub audit trail and release receipt;
- refuses the release without changing production when any check fails.

The current `.github/workflows/production-db-release-request.yml`, `.github/workflows/production-db-release.yml`, `scripts/check-migration-release-lane.sh`, and `scripts/release-production-migration.sh` are the executable release machinery unless intentionally superseded by a later governed contract.

## Security and epistemic invariant

Assistant authority is **proposal authority, not production authority**.

A release request is analogous to a claim submitted to an adjudication membrane: the request may identify what should be considered, but it cannot certify its own correctness or execute itself.

This rule exists specifically so future assistant sessions do not solve missing connector capabilities by weakening database custody or bypassing the protected release path.

## Implementation status

The Issue-based request seam is now implemented on current `main` by `.github/workflows/production-db-release-request.yml`.

That workflow accepts only open OWNER-authored Issues whose title begins with `Production release request:` and validates the exact request fields before checking canonical source/custody and dispatching the protected `production-db-release.yml` workflow from `main`.

This document does not broaden production authority. It records the governance contract around the already-present protected release machinery.