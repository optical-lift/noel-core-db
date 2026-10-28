# Atlas Proper — one event-sourced Work lifecycle, Gates 0–1

**Authority:** User selected Option E (one immutable Work lifecycle, one eventual universal Done transition/receipt). This candidate is an **additive shadow source**. It does **not** introduce another Done API, change existing Result contracts, modify user permissions, mark Work complete, publish a browser reader, or deploy schema.

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

## Not Done / exact next protected gates

1. **Signed/source authority tests:** test accepted signed governor, Anna, outsider, revoked Person and alternate readers. Gate 1 has no browser API, so no user write is authorized by it. Future transition service must reuse existing native-Person/Household authority and exact Work/Result identity.
2. **One transition authority, not a writer adapter zoo:** migrate ordinary, connected-person and owner-witnessed Work to one transactionally governed lifecycle command. Reclassify the eight domain-specific policies as **evidence validators**; they cannot independently say Done. Keep one universal result receipt and stable action ID.
3. **One consequence boundary:** accepted domain actuals (care, pot-up, communications, laundry, Events) reference the one transition. Idempotent physical consequences, no duplicate source application. No clock/event inferred as physical truth.
4. **Bitemporal historical backfill:** never copy a legacy status into a fictitious signed result. A baseline's `recorded_at` is import time; `originalWorkCompletedAt` is an original recorded date, not retroactively attested. Preserve Result and Acceptance rows exactly.
5. **Source-enforced transition cutover:** only after shadow state/authority parity and signed end-to-end validation, disallow direct terminal-state writes and retire independent completion writers. Today/Ledger/Household/Events read the same event-derived state.
6. **Proof gaps:** the live Work inventory contains no Household custody rows. Test synthetic bounded household fixtures before claiming cross-domain completion. Also demonstrate replay, concurrency, plan/campaign continuation, and reject/partial/blocked outcomes.

**Important:** Gate 1 is an observation stream, not the authoritative Work state yet. It is intentionally incapable of Done. PR #475 in `optical-lift/atlas` is held as a draft because it encodes a multi-contract receipt compatibility path the Option E selection supersedes. Do not merge that PR as permanent architecture.

**Release posture:** Candidate-only, no migration applied, no CI/release bypass, no new provider. RiverSong private-repository CI is required before any protected cutover. The project governance prohibits treating a blocker as authorization to enlarge deployment or permission scope.
