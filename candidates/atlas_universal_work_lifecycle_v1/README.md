# Atlas Proper — one event-sourced Work lifecycle, Gates 0–2

**Authority:** User selected Option E (one immutable Work lifecycle, one eventual universal Done transition/receipt). This candidate is an **additive shadow source plus one private first-slice transition authority**. It does **not** expose a Done API, change existing Result contracts, modify user permissions, mark Work complete, publish a browser reader, or deploy schema.

## Existing custody, verified read-only on 2026-10-28

- 230 existing canonical `atlas.work_items`, including 72 recorded completed.
- 36 existing `work_execution_results`, 32 `work_result_acceptances`.
- 40 of the 72 completed Work records have no accepted Result; these are **historical state observations, not freshly established physical actuals or signed completions**.
- 208 existing allocations and 46 original execution-plan events.
- Legacy source remains: 1,404 `atlas.tasks`, 999 `task_transitions`, and 1,114 `task_outcome_events` at audit. These are not migrated into new active tasks or re-executed.
- 10 direct triggers on `work_items` and 119 on legacy `tasks` were present. The catalog writer scan in `00_gate0_baseline_and_writer_census.sql` is a starting point, **not a complete dynamic-SQL audit**.
- This counts-as-of snapshot must be recaptured immediately before a later release; records may change in the meantime.

## Files

1. `00_gate0_baseline_and_writer_census.sql`: read-only origin counts, function source hashes and trigger inventory.
2. `01_shadow_event_source.sql`: *the* eventual canonical immutable lifecycle event table. Private, RLS-enabled, zero client grants. One sequence per original Work, one custody (Org XOR Household), original-source IDs, attributed vs unattributed evidence, effective vs recorded time. No broad payload copying.
3. `02_baseline_and_shadow_observers.sql`: bounded idempotent provenance-only import and one observer for already-authorized original source writes.
4. `03_shadow_projection_and_observers.sql`: private parity projection and observers for Work creation/change, Result, Acceptance, responsibility and plan events.
5. `04_shadow_release_candidate.sql`: exact atomic SQL assembly. A single transaction locks originals, seeds, and then attaches observers so there is no migration gap. **Do not apply without signed/release review.**
6. `05_rollback_postconditions.sql`: checks original counts and source links, no invented accepted result, stream privacy and immutability, original Work forward observation, historical replay without duplicate, and parity.

## Verified rollback test

Using the **live Noel table shape** and exact candidate, with the final COMMIT replaced by postconditions and ROLLBACK:
- Original 230 Work have **zero shadow state mismatches**.
- Original evidence references match exactly; no result/acceptance fabricated.
- Existing 40 unproven historical completions remain distinguished as such.
- An artificially inserted and cancelled Work produced one Work establishment and one state-change observation; neither a Result nor Acceptance was created.
- A second baseline import preserved the projections without duplicate history.
- Source row change/delete was refused, browser/API roles had no shadow stream privileges.
- The final count within the transaction was 231 Work and 554 events (**includes exactly one artificial Work and two artificial events**). After rollback, neither artificial nor imported rows remained.

## Gate 2: ONE private terminal transition authority

- `06_single_transition_authority_private.sql` extends the **same** immutable lifecycle event stream with `work_transition_applied` and a unique, per-original-Work action identity. It defines **one private** `apply_work_lifecycle_transition_internal_v1(work, transition, acceptedResult, actionKey)` with **no authenticated, anonymous, service-role or public API EXECUTE**. This is neither a competing Done path nor a released Work API.
- First admission slice is intentionally narrow: a current native responsible Person (or exact same-Person self adoption) who reported an original `ordinary_company_work_worker_attestation_v1` Result that has already been accepted; exact original Work, Organization, allocation, reporter, Result, Acceptance, contract, idempotency key, current Subject disclosure and work state are checked. It **fails closed** for household, manager adjudication, Event, farm, pot-up, communications and other domain evidence; owner-witnessed ordinary Work has the separately source-checked Gate 2A above. These will all enter the *same* service later after their proofs.
- The Result/Acceptance remain original evidence; one transition event supplies the universal `universal_work_lifecycle_transition_v1` receipt. Repeating its action ID replays the same event and timestamp, not a second Done.
- The original mutable `work_items` state and responsible allocation state are updated only as backward-compatible projections of this event. The existing shadow observer was corrected to avoid recording a duplicate terminal state event for that very same event; the state reducer now includes `work_transition_applied`.
- `07_single_transition_rollback_postconditions.sql` checks API privacy, unsigned/wrong action/missing evidence failures, exact accepted source identity, real original Work projection, one lifecycle event, zero duplicate terminal observations, exact idempotent replay, source evidence preservation and zero parity mismatches. Its SQL uses `request.jwt.claim.sub` emulation to exercise a known existing accepted source; this **is not** a signed GoTrue browser acceptance test.
- The Gate 2 test passed 2026-10-28 in a single transaction on the live database **with final ROLLBACK**. Neither the event stream nor the transition function was installed.
- No domain physical consequences are invoked from this bounded ordinary-Work test. Domain-specific physical and financial effects must remain source-qualified and idempotent in the final authority cutover.

### Exact candidate test order

Run `04_shadow_release_candidate.sql` **with its terminal COMMIT omitted**, then `06_single_transition_authority_private.sql`, then `05_rollback_postconditions.sql`, then `07_single_transition_rollback_postconditions.sql`, and **ROLLBACK**. Do not merge these files as a production migration merely because this structure and simulated-identity proof pass. A live signed worker/owner/outsider/withdrawn access test and protected clone with real cross-domain outcomes are still required.

## Gate 2A: native Ledger governor witness — SAME transition authority

- Expanded `06_single_transition_authority_private.sql` without adding a second Done function or receipt. An accepted `owner_witnessed_person_result` for ordinary Work may go through `apply_work_lifecycle_transition_internal_v1` only after exact original reporter/User/Person matches, `owner_witness` mode, 16–2000 character witness evidence matching the Acceptance, exact responsible allocation, canonical responsible Person, and **present native Ledger governor authority** verified by `company_work_native_ledger_owner_self_v1`.
- The reporter (the governor clicking Done) and the accountable performer (the worker) remain separate in the universal receipt and immutable event. `performanceIsWitnessedClaim=true` does not falsely claim the governor performed physical work. Owner witness does **not** borrow the worker's login, employee seat or a task-specific grant.
- `08_owner_witness_source_negatives_rollback.sql` reuses one genuine historical accepted owner-witnessed Result without changing that evidence. It confirms wrong Person and unsigned attempts are denied, and a synthetic `request.jwt.claim.sub` does **not** substitute for a real root-authorized Atlas session. All Work/event counts remain unchanged after rejected attempts.
- **Signed positive witness acceptance remains outstanding.** The root validator correctly rejects the SQL-emulated owner with `Current authenticated Atlas session required`. Do not weaken the validator, call this a passing signed test, or deploy the witness branch without a real authenticated governor and a reversible test Work.
- The original private ordinary completion and idempotent replay tests still pass with zero lifecycle state mismatches, and `04 + 06 + 05 + 07 + 08 + ROLLBACK` passes as one transaction.

### Management and approval — explicit gating, not legacy authority revival

Live Noel audit: 14 accepted `management_adjudication_v1` Results from the older management override path, but **zero** `ordinary_company_work_manager_acceptance_v1` Results and zero `institutional_adjudication_authority` Acceptances. An explicit current `company_work_adjudication_authority_grants` record exists, but it has no accepted target Result fixture yet. The older override checks older farm/organization memberships and may update execution adapters, plans, and allocations as additional consequences. Therefore **none of those historical override writers are admitted to the new terminal event authority by inference**.

The next controlled migration must create a genuine accepted-management test Work under the current **explicit** authority (not employee or retired farm membership), prove the accepted Result and actor from a real signed session, then route its final transition through the **same** lifecycle function while preserving the original institutional decision and any plan/adapter effects. Rejecting, partial/blocked work, and owner-witness claims must never be mistaken for an accepted Done. The physical effect writers and recurring bed successor must be tested separately but use the one transition receipt.

## Not Done / exact next protected gates

1. **Signed/source authority tests:** test accepted signed governor, Anna, outsider, revoked Person and alternate readers. Gate 1 has no browser API, so no user write is authorized by it. Future transition service must reuse existing native-Person/Household authority and exact Work/Result identity.
2. **One transition authority, not a writer adapter zoo:** migrate ordinary, connected-person and owner-witnessed Work to one transactionally governed lifecycle command. Reclassify the eight domain-specific policies as **evidence validators**; they cannot independently say Done. Keep one universal result receipt and stable action ID.
3. **One consequence boundary:** accepted domain actuals (care, pot-up, communications, laundry, Events) reference the one transition. Idempotent physical consequences, no duplicate source application. No clock/event inferred as physical truth.
4. **Bitemporal historical backfill:** never copy a legacy status into a fictitious signed result. A baseline's `recorded_at` is import time; `originalWorkCompletedAt` is an original recorded date, not retroactively attested. Preserve Result and Acceptance rows exactly.
5. **Source-enforced transition cutover:** only after shadow state/authority parity and signed end-to-end validation, disallow direct terminal-state writes and retire independent completion writers. Today/Ledger/Household/Events read the same event-derived state.
6. **Proof gaps:** the live Work inventory contains no Household custody rows. Test synthetic bounded household fixtures before claiming cross-domain completion. Also demonstrate replay, concurrency, plan/campaign continuation, and reject/partial/blocked outcomes.

**Important:** Gate 1 is an observation stream, not the authoritative Work state yet. It is intentionally incapable of Done. PR #475 in `optical-lift/atlas` is held as a draft because it encodes a multi-contract receipt compatibility path the Option E selection supersedes. Do not merge that PR as permanent architecture.

**Release posture:** Candidate-only, no migration applied, no CI/release bypass, no new provider. RiverSong private-repository CI is required before any protected cutover. The project governance prohibits treating a blocker as authorization to enlarge deployment or permission scope.
