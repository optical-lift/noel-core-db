# Event Work owner-recorded completion — candidate acceptance and authority audit

**Status:** Review-only companion to `candidates/atlas_event_owner_recorded_completion_no_testimony_v1.sql`. No live migration or production deployment is authorized by this file.

## Core claim
An authenticated governing Ledger owner may record **institutional completion status** for an original assigned Company Work item connected to an exact active Event, without falsely claiming worker self-attestation or eyewitness evidence. The writer must preserve original Work ID and append-only result/acceptance history, with source-qualified actor and allocation identities.

## Preconditions and checks
1. Compare candidate source with the *current live* `atlas` function catalog and the applied migrations `20261025210219`, `20261025210452`, `20261025211045`, `20261025211116`.
2. Verify the signed-in Person has an active **Organization-owner membership**, not only a Ledger connection or a governing-Principal seat; then check relevant table triggers and helper signature contracts in a disposable production-shaped schema clone; especially completion/allocations guard triggers and unique idempotency indexes.
3. Confirm `reported_by_user_id` and optional `reported_by_institutional_person_record_id` have the correct actual actor; confirm accepted result does not assert `performedByPersonId`.
4. Confirm the exact bound Event relation remains active and not removed, and `nativeLedgerId` is present for each admissible original allocation establishment kind; if any legitimate kind differs, preserve unknowns rather than broadening the predicate casually.
5. Verify authenticated grants ONLY; `anon` and `PUBLIC` have no EXECUTE on both wrapper and internal source. Verify effective invoker privileges for the SQL public wrapper.

## Must-pass tests (disposable DB clone, seeded controlled fixtures)
- **T01** governing Ledger owner + active exact Event + active responsible Person + ordinary Work contract: zero-text owner-recorded completion succeeds; result and accepted receipt refer to original Work; active allocation moves to completed; no new Work item.
- **T02** optional owner note: note retained as an owner note; no witness-evidence or worker-self-report assertion.
- **T03** same stable source action after successful completion: idempotent return with identical result and acceptance IDs and no second result.
- **T04** reused source action with changed Work/actor/recipient/owner note: rejects collision, no side effects.
- **T05** concurrent owner/worker completion: one accepted terminal result, no silent double completion; actor/result relation remains truthful.
- **T06** owner with real Ledger authority but wrong Event binding or removed Event relation: denied.
- **T07** authorized Ledger Person without governing-owner authority: denied. A governing Principal/Ledger seat without an active Organization-owner membership is also denied.
- **T08** authenticated foreign-Ledger owner / other Organization: denied; neither source nor result existence leaks.
- **T09** anonymous or no Principal/Person: denied; `anon` has no EXECUTE.
- **T10** stale expected allocation after reassignment: conflict, not completion of the new person's work.
- **T11** zero or multiple active responsible allocations: fail closed; do not guess.
- **T12** specialized Work result contract: refused; no bypass of domain results, inventory or booking truth.
- **T13** old Event-only checklist writer remains revoked; the candidate does not re-enable it.
- **T14** previously accepted church-calling Work (read-only real specimen) must never be modified by tests.
- **T15** accepted result remains immutable under existing audit guards; correction path is a later separately governed command.
- **T16** simulate RPC response loss after database commit: original Work/action receipt can be retrieved idempotently, and application displays the committed state rather than an unverified failure.
- **T17** application Event, Work Focus, Today and Company Work projections converge after action without task duplication or broad unauthorized refetch.

## Candidate launch order
1. Security review and clone tests; revise candidate based on actual trigger, privilege and idempotency evidence.
2. Convert reviewed candidate to **one** tracked `atlas_` migration in `noel-core-db` using repository migration-generation procedure; reconcile live migration history.
3. Obtain separate schema release authorization; apply/verify migration.
4. Integrate Atlas application only after governing RPC exists in the intended target environment, while preserving old Event-only handling exclusively for historically eligible records.
5. Authenticated cross-account and notebook visual acceptance; separate Preview and Production approval, no automatic deploy.

## Explicit exclusions
No change to work authoring, allocation standing policy, Event identity, witness-required API, self-reported worker API, Person/seat status, Ledger ownership, deployment, Vercel, CI, live Harvest Party data, or downstream domain effects.

## Report fields required at review close
Commit SHA, migration name/version, exact source functions, test result matrix, security grants, sample receipt IDs from safe fixtures, application PR/commit, signed-in accounts used (without exposing credentials), current Production SHA, unauthorized operations not performed, and remaining limitations.
