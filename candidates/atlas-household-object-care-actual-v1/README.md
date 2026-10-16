# Atlas Household Object Care Actual v1

Status: **inert SQL candidate; not migration-identified, not schema-clone-validated, not merged or released**.

## Purpose

This is the exact-object physical-result side of the universal Reality Workbench. The app currently preserves a person's words as first-party Personal Reality evidence. That is not a Cleaning result.

This candidate supplies a separate governed command to record a *reported physical actual* against one already established, confirmed household care **object and Cleaning requirement**. It uses the same household Evidence/Claim membrane selected for Laundry actuals. No invented room, generalized task, or duplicate Ledger is involved.

## Required unreleased dependencies

- `20260910054000_atlas_personal_cleaning_spaces_object_care_v1.sql` for `atlas.household_care_objects` and `atlas.household_object_care_requirements`. It is present in canonical source, **not production-live**.
- `candidates/atlas-household-claim-evidence-membrane-v1` for `atlas.record_current_household_claim_evidence_api_v1(jsonb)`. It is an **unreleased candidate**.
- An existing authenticated current Principal and current active Household, and an explicitly author-confirmed object/requirement.

**Do not deploy this candidate, individually or by copying it into `supabase/migrations`.** The dependent candidates must first be separately reconciled, source-generated, clone-validated, merged and released through their authorized lanes.

## Exact physical-actual contract

`record_personal_cleaning_object_actual_self_api_v1` receives only:

- `sourceActionId` — stable identity for the exact human action, reused on retry
- `objectId` — canonical UUID, not a phrase like “upstairs toilet”
- `requirementId` — canonical matching object Cleaning requirement
- `transition` — `care_performed`, `care_partially_performed`, or `care_blocked`
- `occurredAt` — explicitly supplied offset-aware timestamp
- `captureId` — optional, current owner's Personal Reality testimony reference

Everything else is rejected. No client-supplied Household, Person, condition state, Clock decision, result owner, service-role claim, or completion grant is admitted.

The owning writer verifies the signed-in Principal's current Household; active confirmed care object; active matching Cleaning requirement; optional capture ownership; recognized transition; explicit physical time; and retry equality through the existing Evidence/Claim idempotency membrane.

It writes **one scoped first-party physical-actual Evidence plus observed Claim** on the exact object, preserving the requirement ID and time.

## What it does NOT establish

An explicit report that a toilet was scrubbed does **not** prove:
- that the complete room is restored;
- that a user-specified result has been independently inspected;
- that any other bathroom object was addressed;
- that an arbitrary task/obligation is closed;
- that the next recurrence has been calculated;
- that work should have the floor in Today;
- that a person is assigned as employee, worker, or household carrier.

A separate source-owned consequence/occurrence resolver must decide whether that actual satisfies a particular open requirement. No checkbox can create that implication.

The candidate deliberately refrains from mutating generic `care_current_state` for the whole room.

## Acceptance prerequisites

1. No cross-household object/requirement or raw capture can be used.
2. No candidate (unconfirmed) or inactive object may be acted upon.
3. A requirement ID for the wrong object fails.
4. Unsupported transition and missing/unzoned time fail.
5. Same sourceActionId, same bytes returns existing actual without duplicate.
6. Same sourceActionId, different object/transition/time fails.
7. One successful operation creates Household Evidence + Claim with the exact object identity and original evidence provenance.
8. It does not create or update a generic task, Clock slot, recurrence, full-room condition or employee assignment.
9. Anonymous role cannot execute either private or public function.
10. Existing RPC custody and zero candidate-introduced lint errors are proved in a production-shaped disposable clone.

## Promotion sequence

Reconcile prerequisites; review candidate SQL and postconditions; generate a canonical migration identity through `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md`; validate in a disposable production-schema clone; obtain independent production release authority. Only then integrate the Workbench's explicit physical-action confirmation and canonical read-back.

The current Atlas PR #291 remains fully safe to test without these commands because only raw testimony capture is enabled.
