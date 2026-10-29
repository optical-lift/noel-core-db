# Atlas Proper — existing original Work self-assignment source correction

**2026-10-29 · Source-only candidate · unreleased.**

## The reproduced defect
The installed `atlas.connected_ledger_person_choices_self_api_v1` returns authorized native Ledger-connected Persons except its own caller (`e.id<>v_self` appears in both the page and hasMore count). Existing Event and ordinary original Work editors consume that source, leaving the signed-in Person absent from responsibility choices.

The original decomposed Work writer `atlas.owner_direct_assign_existing_original_work_self_api_v1` also rejects `v_owner=p_target_person_id`, even though it has already source-verified the actual native Ledger governor and the target must have an independently verified genuine native Ledger connection.

## Smallest safe correction
- Preserve the same Person-choice reader, native authenticated session requirement, active Ledger seat, active canonical Person status, strict pagination, and existing response contract.
- Include the signed-in Person in both the page and pagination `hasMore` semantics. This is a **choice list**, never a permission grant.
- Permit the actual native Ledger governor to assign **their own identity** to the existing original decomposed Work **only if** the same genuine native Person/Ledger connection check, exact original Subject/Work provenance, Work eligibility, one-active-responsible-allocation exclusion, idempotency/plan/Result constraints and existing source security still pass.
- Preserve other eligible Persons, unchanged actor/reporter identities, no new Work, no new employee seat, no forced work-on date.
- No changes to generic Work Done, Event Work, household, private Subject reads, legacy task engine or old farm membership paths.

## Current evidence and hard hold
These two replacement definitions were taken from the current read-only production `pg_get_functiondef`, with expected MD5 guards:
- Person choices: `98d5daf1edf7a62da1e161d5cfa9e61f`
- Original split direct assignment: `22317b744f4c82fcf58562d3fb1934df`

`candidate.sql` uses original function signatures, security mode and volatility, and guards the exact source snapshot before applying. `postconditions.sql` checks unchanged native identity/authority/Work custody invariants.

**Not production-applied. Not versioned. No signed acceptance has occurred on this candidate.** Static source comparison is not enough to make this releasable.

## Required signed acceptance, in a disposable production-shaped clone
1. Genuine GoTrue governor signed into a Ledger with native active seat: the chooser includes their **own canonical Person ID once**; another eligible connected Person remains; page boundary/cursor/hasMore do not omit or duplicate either.
2. Another authorized connected Person sees only Persons permitted by the existing Ledger reader. An unrelated Ledger, disconnected seat, anonymous request, and missing/expired native connection cannot list/assign.
3. Governor assigns **themselves** to an existing eligible original split Work with `p_service_date=NULL`: same original Work ID, exactly one native responsibility, no plan, no offer, no employee-seat grant, no private Subject disclosure.
4. Governor assigns themselves a date only when the existing plan window permits; clearing/moving that date does not copy Work or change authority.
5. An eligible different Person still works as before. Wrong-Ledger, non-governor, canceled original Work, unrelated original Work, conflicting active allocation, stale action ID and changed replay arguments are rejected without side effects.
6. Verify genuine signed Work Focus, My Work and Today readback, then signed own Result/accepted Done with correct actor and historical receipts.
7. Confirm no extra data through Event, Subject, older farm readers or counts, and unaffected Household and Event regressions.

Only after those gates pass: owner source review, merge exact candidate, governed migration generation, protected clone of **generated** bytes, explicit production release, signed browser acceptance. This change cannot be used as an excuse to deploy outstanding unrelated drafts.
