## Convergence Gate 1–2 — installed-source map and shared lifecycle contract (2026-10-29)

**Status: SOURCE AUDIT + INTERFACE DECISION, NOT PRODUCT CODE OR A RELEASE.**
This is the compact dependency reconciliation requested across the latest
Dropbox /Lex/Atlas handoffs (October 26–28), checked against live Noel
catalog/function definitions and exact held PR heads on October 29.
Keep all existing branches; no new data model, migration or release approval.
The 2026-10-28 Foundry operating-rhythm handoff is the controlling **Anna
operating acceptance**; the October 26 canonical Work stabilization handoff
controls the **first original-Work source seam**. They are not separate task
engines and neither supersedes the other's security rules.

### A. Exact source → governed operation → consuming surface

| Capability | Installed authority / source | Held draft and dependency | Convergence / verification |
| --- | --- | --- | --- |
| Original Work | `atlas.work_items`, original Organization/Household custody, typed `work_item_context_links`; source and Subject guards from merged #2265 | #2368 lifecycle shadow; #2362 care originals; Atlas #462 Today already merged | One original ID from Ledger/Subject/Program/Event/Today. No new copy table or farm-specific task engine. Verify historical + current states and alternate readers. |
| Native Person + disclosure | Canonical Person, native Ledger relevance and per-original disclosure; bounded legacy farm readers (merged #2265) | #2385 source-authorized rhythm discovery; Atlas #477 reader; historic #2368 files 16–19 | Re-evaluate at every read/action, per actual Subject/field; legacy membership never makes authority. Signed worker/outsider/revoked read matrix; no counts/titles/side channels. |
| Need + governed policy | `atlas.rhythm_rules/bindings/state/satisfactions` and source Subjects; old farm conditions are evidence, not necessarily current | #2362 observed-need + standing-source candidates; governed Rulebook version/binding tables **not installed** | Two eligibility modes share one Need evaluator: **owner-approved standing stewardship** needs no alleged fresh defect; **corrective intervention** needs source-qualified observed condition. Different evidence policies, same original Work, not two generators. |
| Current Work establishment | Existing native Ledger Work, offer/uptake, scoped responsibility and direct-original writers, with their own narrower provenance limits | #2362 observed writer (05), standing-source admission (17); #2368 historic current-Need lineage **missing** | Atomic original Work + true Ledger/Subject/source links, one active serving per Need/Subject/window, stable source/idempotency and explicit current governor/source approval. No blanket historical reactivation. |
| Assignment | `atlas.work_allocations`, current native establishment basis, transfer/offer scope; original direct assignment RPC currently includes a service-date parameter | Atlas #471 governor transfer UI; other held source work | Responsibility independent of scheduling; current Person and exact Ledger checks, no invented employee seat or duplicate active carrier. Direct existing-original obligation and offered acceptance remain distinct lawful entry methods. |
| Work-on plan / Today | `atlas.work_execution_plans` + immutable plan events; live `connected_person_place_work_self_api_v1` now includes root-Ledger check *after* requiring actor=current assignee; Atlas #462 merged Today lens | Atlas #477 care Today consumer | Governor scheduling must be independently usable for someone else's Work; worker responsibility is not scheduling grant. Distinguish planned day, due date, Clock admission, carry-forward, overdue and unscheduled. Source inspected; genuine signed actor matrix/browser proof **not yet recorded here**. |
| Original Result / Acceptance | `atlas.work_execution_results` + `atlas.work_result_acceptances`; multiple installed source-specific writers | #2362 care signed physical Actual (10); #2368 single transition (06); #2368 old-Result preservation | Partial/blocked/attended/acceptable/winter-ready are typed reports with source qualification, not generic Done. Only accepted and qualifying result can drive a modern `completed` transition. One Result/Acceptance identity; source receipts, no fabricated history. |
| Complete / Done | Live `work_items.work_state`, existing disparate completion writers and triggers; **no** live `work_lifecycle_events_v1` | #2368 private `apply_work_lifecycle_transition_internal_v1` supports **complete only**, creates one event + mutable projection | ONE authoritative completion transition after adapter cutover, per original + stable action/evidence; no second Done from shadow observer. Include Event shared state confirmation without claiming physical performer, household and Program regression before universal claim. |
| Cancel / retire | Live `company_work_retirement_preflight_self_api_v1`, `retire_company_work_with_reconciliation_self_api_v1`, dependency guard and institutional `not_relevant` adjudication. These are old Company/legacy-source contracts | #2368 does **not** yet provide canonical cancellation transition | Historic `obsolete_cancelled` review is evidence, not itself cancellation. Current native governor+exact Ledger authorization, dependency snapshot/token reconciliation, old Results retained, then exactly one native lifecycle retirement event and projection. The older legacy Task/slice reconciliation writer cannot be reused as-is for self-adopted originals. |
| Supersede | Live `work_state='superseded'` permitted, `superseded_by_work_item_id` column | No admitted general single transition in #2368 | Do not use to imply completion, automatically create a replacement or erase unresolved evidence. Require explicit original successor linkage and own admitted lifecycle gate before activation. |
| Historical review | Existing accepted Results and legacy tasks/memberships remain old evidence. Live historic review table/function **absent** | #2368 16–19 append-only `person_confirmed`, `worker_pending`, `governor_reviewed`; `historically_performed/obsolete_cancelled/still_unresolved` | Governor disposition has no effect on original state today. Source decisions must not grant responsibility/seat/Done. Truthful terminal representation of historical performance still an **open semantic/code gate**, not permission to create a retroactive accepted Result. |
| Shared client displays | Atlas #462 unified Today source and existing Work Focus, Index/Ledger/Event consumers | Atlas #477 care lens, #471 owner transfer; Atlas usability #487 | The same source ID/receipt and lawful actions in every surface. Event identity filter now exists in live `ledger_occurrence_shared_index_self_api_v1`; cross-surface signed negatives still required. Notebook draft loss #479 independently stop-ships affected UI. |

**Live catalog checkpoint, not an approved mutation target:** 232 original
`work_items` (139 open, 73 completed, 20 cancelled, 0 superseded);
38 execution Results, 33 Acceptances, 214 allocations, 35 plans,
47 plan events. Of the 73 completed original Work rows, **40 have no
linked accepted Result**. These are historical state claims that cannot
be upgraded to a fabricated signed/accepted performance through backfill.
Do not equate the count with undone tasks. The catalog-based writer
census in file 00 finds numerous source-specific functions; it is
non-exhaustive for dynamic SQL and trigger-mediated mutations.

### B. Shared lifecycle interface: accepted invariant versus open gate

1. **Identity/custody (accepted):** Source owns one stable original
   `work_item_id`; events are append-only and sequence-ordered per Work.
   The current signed actor, native Ledger/Household authority, source
   evidence, idempotency/action identity and original custody are
   independently verified. Current disclosure is not granted by a legacy
   assignment, historical Person link, associated Subject ID or mere
   possession of a Ledger seat.
2. **State vocabulary (accepted):** `open`, `completed`, `cancelled`,
   `superseded` are distinct original Work states. A modern
   `completed` means accepted **qualifying** Result or an explicitly
   defined non-performance shared-state contract—not a historical
   opinion, elapsed interval, title change or checklist coincidence.
   `cancelled` means no longer a current obligation, **not** physically
   performed. `superseded` requires exact successor provenance.
   `still_unresolved` is a review verdict; it is NOT a new Work state.
3. **Single transition custody (accepted design; held implementation):**
   Every admitted *new* terminal action must append exactly one
   authoritative `work_transition_applied` event and project the same
   original mutable state atomically, after source authorization and
   source-specific invariants pass. Historical snapshot/observer events
   are observations, never substituted for an authoritative transition.
   The #2368 function currently implements only `complete`; adding
   cancel/supersede must extend **this lifecycle**, not mint parallel
   completion/cancellation streams.
4. **Result truth (accepted):** Distinguish reported, accepted and
   genuinely terminal. Original Results/Acceptances are immutable
   references; worker progress/partial/blocked and qualified physical
   Actual may drive different Need outcomes. Historic evidence-only
   review never inserts a signed contemporary Result or fabricates a
   backdated actor/acceptance.
5. **Retirement preconditions (accepted; integration open):** Native
   current governor must review exact historical link/outcome, original
   current state, dependency snapshot, required reconciliations, preserved
   accepted evidence and stable action identity. Do not bypass existing
   `guard_company_work_cancel_dependencies_v1`. Current old retirement
   function uses Organization-owner/legacy-task assumptions and
   `organization_management_adjudicate_company_work_api_v1` uses
   membership-era adjudication; neither alone proves a present
   *native Ledger governor* authorization or the unique new transition.
   New cancellation is **not ready**.
6. **New Need → new original (accepted design; source open):** A
   separately established *present* Need/eligibility can mint one
   distinct new original Work with immutable linkage to old history,
   not revive or repurpose the original allocation. Authority, serving
   boundary and concurrency uniqueness derive from current Subject,
   Ledger, approved policy, Need, service window and source action—not
   similarity of titles, refreshes or old unreviewed farm tasks.
   Reconcile a still-current original before admission.
7. **Two policy eligibility modes (accepted from latest handoff;
   code gap):** Owner-approved **standing rotation** can warrant a
   bounded Subject visit without observed physical deterioration;
   qualifying Actual then supplies condition. **Observed corrective**
   intervention must prove fresh source-specific condition. #2362's
   current `standing_source_observed` candidate is a *condition-qualified
   delegated admission*, NOT yet the condition-free owner-approved
   rotation in the October 28 Foundry handoff. Its own gate document
   explicitly disclaims an automatic next-workday generator.
8. **Temporal truth (accepted):** Need eligibility, work-on service day,
   due date, worker scheduling proposal, committed source plan,
   Clock/Today exposure and actual completion time are distinct records.
   No `old overdue → today` silent conversion; no automatic next day
   without established governor release/time policy.
9. **Read/replay and release gate (open):** Under genuine signed worker,
   governor, unrelated connected Person, revoked account/seat and
   anonymous sessions, prove permitted fields and exact denials across
   original and legacy readers, original Work/Result/Event/Household
   parity, idempotent replay, concurrent admission/terminal actions,
   complete→next Need, pending historic review, cancellation dependency
   blockers and rollback. A missing RPC/404 or container-registry failure
   cannot count as signed denial. Exact SHA/production-shaped disposable
   clone, RiverSong and browser acceptance precede any proposed release.

### C. Immediate, bounded implementation order after this interface gate

- **#2368:** Preserve this source interface; implement single canonical
  governed retirement and resolve historical-performed truthful closure
  semantics; do not broaden the old self-adoption Done authority. Finish
  the genuine signed historic fixture after environment failure.
- **#2362 + #2385:** Rebase source expectations on the same terminal event
  contract. Separate routine stewardship from observation-triggered
  intervention; no automatic Next Work or periodic clock generation claim
  until the source policy, deterministic release and signed actor proof
  exist.
- **Atlas #462/#477/#487:** Reuse the single Work Focus and Today source;
  verify Event-disclosure and date authority with signed actors. Do not
  ship the affected notebook while draft-loss/updates and action parity
  are unproved.
- **Anna acceptance:** First genuine connected-Person Work→Result→Ledger
  readback, then full Foundry policy→bounded Work→signed Actual→next
  rightful Work using live disclosed Subject context. Another Ledger
  must configure the same mechanism. No real Elm Work/permissions are
  modified during held validation.

**Gate exit:** Source mapping and interface boundaries recorded,
but **implementation, signed tests, and release remain OPEN**. Existing
GoTrue, old Task, Event, Program and Household adapters are not
declared cut over merely by this record. Source-authority and exact
release audits must be refreshed before a migration is assembled.

## Continuation gate: historical retirement + new Need (2026-10-29; HELD)

**No release approval.** Protected signed historical clone
[#40974684744](https://github.com/optical-lift/noel-core-db/actions/runs/40974684744)
failed in the disposable-clone runner while pulling Supabase container images from
`public.ecr.aws/supabase/postgres:17.6.1.165` (`Data limit exceeded`).
Earlier source/custody steps passed. This is **not a positive or negative
historical authorization result**. The signed historical matrix remains unproved;
the earlier green [#40973367714](https://github.com/optical-lift/noel-core-db/actions/runs/40973367714)
did not exercise the newly merged signed historic test harness. Keep this draft
and the validation carrier #2393 unreleased; do not modify protected CI, image
sources or hosting merely to clear this failure.

**Live-schema read-only findings (not changes):**
- `atlas.work_items.work_state` permits `open/completed/cancelled/superseded`;
  `cancelled_at` is valid only for `cancelled`. Existing accepted-result
  completion guard requires an accepted source Result before ordinary
  `completed` where its result contract is active. Historical governor review
  is **not** an accepted source Result.
- The live `guard_company_work_cancel_dependencies_v1` trigger rejects
  cancellation when requirements, relations, pending offers, worker-week
  projections, execution Results, or active time contracts remain. Do not
  directly UPDATE a Work state to evade these safeguards.
- Reuse the existing owner preflight
  `company_work_retirement_preflight_self_api_v1` and bounded
  `retire_company_work_with_reconciliation_self_api_v1` source behavior.
  The latter currently covers specifically reconciled legacy task/slice
  dependencies, calls the institutional `not_relevant` adjudicator and
  causes a mutable `cancelled` state. It has **not** yet been wired as a
  unique `work_transition_applied` in this held lifecycle. It must not be
  invoked in production as though it were the unified lifecycle.
- The historical reviewer (files 16–19) handles prior self-adopted original
  `atlas.work_items`, whereas existing
  `decide_company_work_legacy_backlog_owner_self_api_v1` is restricted to
  archived `atlas.tasks`. This converter cannot be called with an old
  original Work ID or used to bypass the new-Need admission gate.
- Current `owner_create_native_ledger_today_work_self_api_v1` is a genuine
  original-Work writer under an accepted standing assignment scope, with
  source-action idempotency; it does **not** yet establish exact old
  self-adopted-Work historical lineage or prove single current Need. Never
  turn a historical link itself into an assignment, plan or fresh Work.

**Next source-only implementation order within #2368 / issue #2392:**
1. Repair or re-execute the *same trusted signed historical matrix* within
   authorized runner/registry custody; inspect diagnostics. Do not count a
   404, infrastructure stop or absence of the installed source as denial.
2. Integrate a governor-reviewed `obsolete_cancelled` source decision with
   the **single** canonical lifecycle retirement transition, using existing
   dependency preflight/reconciliation and strict replay/source/actor identity.
   An unresolved decision must leave original Work open. Historical
   `historically_performed` requires a distinct truthful terminal
   representation review; neither a fabricated modern Done nor an
   unexplained `cancelled` relabel is acceptable.
3. Admit any genuine still-current Need through present native Ledger/Person/
   source governance into **one** newly sourced original, with immutable
   old-original lineage and concurrency/idempotency proof. No reassignment
   or resurrection of old historical allocations.
4. Prove the combined exact historical provenance, no accepted Result
   fabrication, no duplicate Work/Done, dependency preservation,
   signed owner/worker/outsider/revoked session and seat, hidden-field read
   denials, and full historical/modern lifecycle replay on a fresh
   production-shaped disposable clone.
5. Only then produce a separately governed release migration and UI
   acceptance. Real Anna Beds 3+4 Work stays unchanged.

This is a **release blocker and integration record**, not a second Work engine,
a permission expansion, a generated migration, or an implementation claim.

# Atlas Proper — one event-sourced Work lifecycle, Gates 0–3C (draft)

## October 29 source addition — native historical review, HELD

Owner decisions #2392 (1C / 2D / 3D) now have a separate
**append-only evidence-only review slice**, files `16`–`19`:
- `16_historical_self_adoption_review_candidate.sql`: immutable historical
  Person-link review events; exact current root-governor confirmation for
  historical `self_adoption` allocation + native Ledger relevance, current
  signed Person+Seat and disclosed-Work guard for pending historical report;
  governor choice `historically_performed / obsolete_cancelled /
  still_unresolved`, requiring a real pending report or old accepted Result
  for a historical-performed finding. Actions are idempotent or deny conflicts.
- `17_historical_self_adoption_review_readback_candidate.sql`: bounded,
  source-authorized governor-only history read, with explicit `hasMore`.
- `18_historical_self_adoption_review_postconditions.sql`: disposable-only
  structural RLS, ACL, immutable trigger, no membership grant and REST facade
  check.
- `19_historical_self_adoption_public_transport_candidate.sql`: narrow
  authenticated-only PostgREST forwarding wrappers; original functions
  enforce current native Person/Ledger/field security, not the web client.

**Important scope:** This review appends *evidence and dispositions*, NOT
canonical Result acceptance or authoritative Work closure. It cannot make
the old Beds 3+4 Work disappear from active Work or create new Work. The
governor's final physical closure of still-open historical Work must be
expressed in a reviewed native lifecycle/retirement transition; it is
**not yet implemented**. Current Need must pass existing separate native
original Work admission and historical-source-link/idempotency review.
Historical Person confirmation does not grant a current seat, read access,
responsibility, or schedule. Do NOT deploy or configure real Elm data from
this source-only candidate until signed owner/worker/outsider/seat/session
denials, old-Result preservation and physical Work state tests pass.

**Live source status:** the old self-adopted writer is still installed in
production and uses historical organization membership, so this new source
and the file 12 fail-closed cutover MUST be released together under the
governed versioned migration only after genuine signed proof. A source
test or SQL grammar green result alone cannot establish live safety.

## Native-only authority correction status (2026-10-29)

**Source modified, not deployed:** `06_single_transition_authority_private.sql` now
rejects `self_adoption` as a new Done authority (even when a historical
membership is still active). `12_self_adopted_original_writer_single_done_cutover_candidate.sql`
is now a signed, fail-closed compatibility entrypoint: it does not write any
Result, Acceptance, lifecycle event, allocation or Work state. Historical
Results remain in their original tables and their immutable shadow lineage;
the old writer does not create a fictitious fresh lifecycle receipt on replay.

Rollback tests `09` and `13` are now **negative/preservation** tests:
they no longer reopen a completed historical Work, they require a denial and
unchanged original Work/Result/Acceptance/event counts. The rollback runner
no longer needs its historical-Work SAVEPOINT. A new standalone source
regression test and CI check enforce the absence of legacy membership admission.
**Source checks/SQL grammar passing are NOT genuine signed GoTrue proofs.**

**Reuse existing native bridge for historical `atlas.tasks`:**
`atlas.decide_company_work_legacy_backlog_owner_self_api_v1` already has a
current native Ledger-governor gate and can record `not_current`,
`matched_existing_work` or `recovered_new_work` into
`atlas.company_work_legacy_task_reviews_v1`. That source leaves old task
history in place, records source identity, avoids duplicate active Work,
and deliberately creates **no allocation or plan**. It is the preferred
existing mechanism for those legacy tasks; do not build a rival converter.
Its old assignee lookup is **historical attribution only**, never an
independent present-day grant. A historical Task is not itself proof of
a current physical Need; owner must verify the need before recovery.
The existing mandatory `p_reason`/owner_reason UI burden needs a separate
user-friendly bounded provenance solution, not a fake explanatory essay.

**Still outstanding:** for self-adopted original `work_items`, add
governor-confirmed native Person/Work lineage via current Ledger authority
using the existing identity reconciliation and source-link substrate; do
not reassign or reopen the old item. A signed worker's historical report
must remain **pending evidence** until a native governor reviews it. A
governor must distinguish `historically_performed` from
`obsolete_cancelled` and `still_unresolved`, without manufacturing
fresh physical Actuals. The action source and genuine signed tests do not
yet exist; neither the old writer nor the universal Done transition may
stand in for them. Current physical need proceeds through the existing
native original Work admission with explicit source lineage and idempotency.

**Release blockers:** source-state and current-main reconciliation;
disposable full-schema compile/rollback; genuine signed owner, worker,
outsider, revoked connection, seat and session tests; historical
provenance/duplicate negative tests; native UI acceptance. Do NOT merge
this draft or generate a production migration until those gates pass.

## Owner's 2026-10-29 legacy-evidence ruling — supersedes historical self-adoption execution design

**Governing choices 1C / 2D / 3D**, documented and acceptance-scoped in [Noel issue #2392](https://github.com/optical-lift/noel-core-db/issues/2392). This draft is **NOT releasable in its current Gate 3B form**. All earlier positive self-adopted-Work tests and guidance below are records of *previous draft behavior*, not current release acceptance.

- A current native Ledger governor may explicitly reconcile old memberships, Persons, Work, and Results to canonical native identities and historical evidence. This does **not** admit old membership as authority or grant worker disclosure, active responsibility, or Done permission. An appropriately bounded owner-approved batch may preserve many original references with one governed decision, while recording exceptions; it may never blanket-grant active Work.
- Historical unfinished Work remains as history. If a current Need truly persists, create **one new** native original Work linked to that source under present authority (not reopen/reactivate the old Work and not an automatic recurrence).
- Currently authenticated workers may provide pending, attributable historical evidence without marking Work complete. A current governor can inspect that evidence and accept substantiated historic completion or retire obsolete Work, explicitly distinguishing performed from cancelled/not-required. Historical evidence must not impersonate a modern physical Result.
- **Source blockers:** `06_single_transition_authority_private.sql` still authorizes a null-canonical-assignee self-adopted allocation through `atlas.organization_memberships`; `12_self_adopted_original_writer_single_done_cutover_candidate.sql` still joins that same legacy authority, and tests `09`/`13` claim old positive semantics. Those paths must be replaced/retired with native-only guards, rewritten denial+preservation tests, and real signed source checks **before any generated migration**. Do not circumvent `check-universal-person-authority.py` or fake a passing migration by copying composite SQL into canonical migrations.
- The single lifecycle/Result/Acceptance/event stream remains the target, and original legacy data is preserved under authorized historical access. Deleting old rows to clear authorization failures is **not** approved.

**Status:** owner decision recorded; code correction and genuine signed acceptance pending. No production mutation.


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

Run `04_shadow_release_candidate.sql` **with its terminal COMMIT omitted**, then `06_single_transition_authority_private.sql`, then `05_rollback_postconditions.sql`, then `07_single_transition_rollback_postconditions.sql`, `08_owner_witness_source_negatives_rollback.sql`, `09_self_adoption_person_rollback.sql`, and **ROLLBACK**. Do not merge these files as a production migration merely because this structure and simulated-identity proof pass. A live signed worker/owner/outsider/withdrawn access test and protected clone with real cross-domain outcomes are still required.

## Gate 2A: native Ledger governor witness — SAME transition authority

- Expanded `06_single_transition_authority_private.sql` without adding a second Done function or receipt. An accepted `owner_witnessed_person_result` for ordinary Work may go through `apply_work_lifecycle_transition_internal_v1` only after exact original reporter/User/Person matches, `owner_witness` mode, 16–2000 character witness evidence matching the Acceptance, exact responsible allocation, canonical responsible Person, and **present native Ledger governor authority** verified by `company_work_native_ledger_owner_self_v1`.
- The reporter (the governor clicking Done) and the accountable performer (the worker) remain separate in the universal receipt and immutable event. `performanceIsWitnessedClaim=true` does not falsely claim the governor performed physical work. Owner witness does **not** borrow the worker's login, employee seat or a task-specific grant.
- `08_owner_witness_source_negatives_rollback.sql` reuses one genuine historical accepted owner-witnessed Result without changing that evidence. It confirms wrong Person and unsigned attempts are denied, and a synthetic `request.jwt.claim.sub` does **not** substitute for a real root-authorized Atlas session. All Work/event counts remain unchanged after rejected attempts.
- **Signed positive witness acceptance remains outstanding.** The root validator correctly rejects the SQL-emulated owner with `Current authenticated Atlas session required`. Do not weaken the validator, call this a passing signed test, or deploy the witness branch without a real authenticated governor and a reversible test Work.
- The original private ordinary completion and idempotent replay tests still pass with zero lifecycle state mismatches, and `04 + 06 + 05 + 07 + 08 + 09 + ROLLBACK` passes as one transaction.

### Canonical performer identity for self-adopted Work

The same receipt distinguishes all three admitted source modes: signed responsible-Person Work, signed self-adopted Work, and a separate governor-witnessed claim. Self-adopted allocations legitimately have `assignee_canonical_person_id=NULL`, so the signer **must be recovered from the original active Organization membership** after exact membership/user validation. The responsible Person cannot be silently recorded as null just because the connection-assignee field is null.

`09_self_adoption_person_rollback.sql` uses a real original self-adopted Work/Result/Acceptance as fixture, reopens it only inside ROLLBACK, and verifies the canonical responsible Person, reporter Person, non-witness claim, one event and exact same-action replay. This and rollback tests 05, 07 and 08 pass in one transaction.

### Management and approval — explicit gating, not legacy authority revival

Live Noel audit: 14 accepted `management_adjudication_v1` Results from the older management override path, but **zero** `ordinary_company_work_manager_acceptance_v1` Results and zero `institutional_adjudication_authority` Acceptances. An explicit current `company_work_adjudication_authority_grants` record exists, but it has no accepted target Result fixture yet. The older override checks older farm/organization memberships and may update execution adapters, plans, and allocations as additional consequences. Therefore **none of those historical override writers are admitted to the new terminal event authority by inference**.

The next controlled migration must create a genuine accepted-management test Work under the current **explicit** authority (not employee or retired farm membership), prove the accepted Result and actor from a real signed session, then route its final transition through the **same** lifecycle function while preserving the original institutional decision and any plan/adapter effects. Rejecting, partial/blocked work, and owner-witness claims must never be mistaken for an accepted Done. The physical effect writers and recurring bed successor must be tested separately but use the one transition receipt.

## Gate 3 candidate — original native Person writer, ONE actual Done engine

- `10_connected_person_result_writer_single_done_cutover_candidate.sql` modifies the **existing** `report_connected_person_company_work_internal_v1` implementation, not its signature, Ledger/Person permission model, original Result table or evidence acceptance rules. It preserves all reporting checks, `partial/blocked/unable` nonterminal evidence and owner-witness distinction.
- On a new accepted **completed** Result, it creates the original Result and Acceptance, then calls `apply_work_lifecycle_transition_internal_v1` to create the **sole terminal lifecycle event** and projection. **The former direct `UPDATE atlas.work_items SET work_state='completed'` and allocation-completion write are removed from this original reporter.** The only Done success receipt is `universal_work_lifecycle_transition_v1`.
- On exact replay, a lifecycle-era acceptance returns the identical canonical event/receipt. Earlier historical already-completed Results remain original evidence and return a versioned `historicalRecordedCompletion=true,newTransitionApplied=false` receipt linked to an existing historical state snapshot, not a fictitious new transition. No historical Work is reopened or falsely re-completed in deployed code.
- `11_connected_person_original_writer_rollback.sql` tests a real **open** Ledger-connected Person's Work. It verifies wrong Person denied, one original Result, one Acceptance, one authoritative Done event, one source projection, identical same-action replay, different-payload collision denied, and zero parity mismatches. The source data and Work state return to their original values with ROLLBACK. The live-shape test passed using an open Elm Work whose reporter/assignee Person mapping resolves correctly.
- The complete Gate 0–3 rollback sequence is `04` (omit COMMIT), `06`, `10`, `05`, `07`, `08`, `09`, `11`, and ROLLBACK. No source-accepted result or real worker Done was created in production.
- This cutover candidate is **NOT** an app deployment. Its universal receipt will require the native Today/Work Focus reader and button to consume the new event-driven acknowledgment, followed by genuine signed governor/Anna/outsider tests. The older self-adoption reporting entrypoint, management, care, Event, household and other result writers still need their independent completion updates removed through this same engine.
- There are currently no `open` Work fixtures with an active self-adopted allocation, so do not fabricate a positive end-to-end original self-adoption reporter test. The private transition was separately validated with an existing, accepted self-adopted historical original Result.

## Gate 3B — one Done for the original self-adopted reporter

- `12_self_adopted_original_writer_single_done_cutover_candidate.sql` modifies the existing `report_self_responsible_company_work_self_api_v1` implementation without changing its signature, source authorization or original evidence. It no longer directly updates `atlas.work_items` or `atlas.work_allocations` when completion evidence is accepted. Both ordinary native connected-Person reporting and original self-adopted reporting now delegate terminal state to **the same** `apply_work_lifecycle_transition_internal_v1` and return `universal_work_lifecycle_transition_v1`.
- Exact action replays use the original Result identity; pre-cutover completed Work uses an explicitly labeled **historical snapshot receipt**, not a new lifecycle transition. Partial, blocked and unable reports remain nonterminal source evidence.
- `13_self_adopted_original_writer_rollback.sql` first confirms an existing accepted historical Result can be replayed **without new events**. Then, rather than reopening a historical Work (which violates the old Ledger Event projection's immutable identity), it creates a new test-only Work and self-adoption allocation with a **real current Organization membership and exact validated responsibility basis** *within ROLLBACK only*. An unrelated Person is denied; the allocated Person's accepted Done creates one original Result, one Acceptance and one lifecycle event. Same-key replay produces the same receipt and timestamp; payload collision is rejected.
- **Fixture isolation is essential**: the older `09_self_adoption_person_rollback.sql` temporarily reopens one historical Work to test the private transition. That creates a temporary authoritative event; subsequent fixture selection would be contaminated. `manual_rollback_smoke.sh` wraps that test in an explicit SAVEPOINT and rolls it back before testing the new synthetic source writer.
- Verified with the production-shaped database: 04 + 06 + 10 + 12 + 05 + 07 + 08 + 11 + SAVEPOINT + 09 + ROLLBACK TO SAVEPOINT + 13 + final ROLLBACK **passes**. The fixture proves code behavior through SQL-auth claim emulation, **not** a genuine GoTrue signed user session.
- All files remain candidates in this draft PR; **no production Work, Results, permissions or schema was changed**.

## Gate 3C — one Done for original shared Event checklist Work

- `14_event_shared_original_writer_single_done_cutover_candidate.sql` modifies the **existing** `mark_ledger_occurrence_shared_work_done_self_api_v1` implementation, not its signature or source Ledger/Occurrence permission checks. It preserves original Result and Acceptance with `shared_checklist_state_confirmation` and **removes its direct Work completion UPDATE**. The existing writer delegates to the SAME private `apply_work_lifecycle_transition_internal_v1` and returns the SAME `universal_work_lifecycle_transition_v1` receipt.
- The common transition now accepts this **one additional evidence mode** after validating exact organization, original Work/Occurrence/active native Ledger association, the exact existing Result/Acceptance, current signed Ledger Person/Event identity, source metadata, idempotency key and explicit statement that the checklist actor **does not assert personal physical performance**. There is no responsible worker allocation for shared checklist state; the event and receipt preserve `responsiblePersonId=null`, `personalPerformanceNotClaimed=true`, and `authorityMode=event_shared_state_confirmation`. The signed actor is the marker, NOT an invented physical performer.
- Older accepted Event checklist completions are still preserved as historical state with their original result IDs, not re-signed lifecycle events. Same-key replay after a new lifecycle transition must recover the same event and timestamp; already-completed Work cannot create another Done.
- `15_event_shared_source_negative_rollback.sql` uses one of the three original Event checklist histories. It verifies original Result/Acceptance *did not* claim physical performance, rejects a different Person, rejects a missing GoTrue session and rejects a forged synthetic reporter claim through the existing `ledger_occurrence_shared_work_actor_self_v1` reality-access guard. It checks **zero changes to original Work, Result, Acceptance or lifecycle events**.
- The complete rollback suite including original connected-Person writer, self-adopted writer, owner witness negatives and Event negatives passes in a **single BEGIN/ROLLBACK transaction**. `manual_rollback_smoke.sh` now includes the Event candidate and negative source test, with the self-adoption test isolated by SAVEPOINT.
- **Positive signed Event acceptance is NOT proven.** SQL claim emulation cannot pass `reality_access_self_api_v1`; only a real authenticated Ledger-connected Person with exact Event disclosure can validate the happy path. Keep this cutover closed until that signed test, same-key replay and absence of duplicate physical outcomes pass on the protected runner.
- Management legacy overrides, approved domain actuals, communications and household still need the same-source migration. This addition has **not** been deployed or used to mark any real Event Work Done.

## Not Done / exact next protected gates

1. **Signed/source authority tests:** test accepted signed governor, Anna, outsider, revoked Person and alternate readers. Gate 1 has no browser API, so no user write is authorized by it. Future transition service must reuse existing native-Person/Household authority and exact Work/Result identity.
2. **One transition authority, not a writer adapter zoo:** migrate ordinary, connected-person and owner-witnessed Work to one transactionally governed lifecycle command. Reclassify the eight domain-specific policies as **evidence validators**; they cannot independently say Done. Keep one universal result receipt and stable action ID.
3. **One consequence boundary:** accepted domain actuals (care, pot-up, communications, laundry, Events) reference the one transition. Idempotent physical consequences, no duplicate source application. No clock/event inferred as physical truth.
4. **Bitemporal historical backfill:** never copy a legacy status into a fictitious signed result. A baseline's `recorded_at` is import time; `originalWorkCompletedAt` is an original recorded date, not retroactively attested. Preserve Result and Acceptance rows exactly.
5. **Source-enforced transition cutover:** only after shadow state/authority parity and signed end-to-end validation, disallow direct terminal-state writes and retire independent completion writers. Today/Ledger/Household/Events read the same event-derived state.
6. **Proof gaps:** the live Work inventory contains no Household custody rows. Test synthetic bounded household fixtures before claiming cross-domain completion. Also demonstrate replay, concurrency, plan/campaign continuation, and reject/partial/blocked outcomes.

**Important:** Gate 1 is an observation stream, not the authoritative Work state yet. It is intentionally incapable of Done. PR #475 in `optical-lift/atlas` is held as a draft because it encodes a multi-contract receipt compatibility path the Option E selection supersedes. Do not merge that PR as permanent architecture.

**Release posture:** Candidate-only, no migration applied, no CI/release bypass, no new provider. RiverSong private-repository CI is required before any protected cutover. The project governance prohibits treating a blocker as authorization to enlarge deployment or permission scope.

## Gate 3D — source-qualified physical care integration (held; October 28)

- The SAME private `apply_work_lifecycle_transition_internal_v1` now admits one additional accepted evidence mode: `continuing_care_actual_v1` tied to an exact original `rhythm_state` Work. A terminal Result requires the exact signed Person and active original Ledger responsibility, first-party `care_result_events`, `care_observation_events`, accepted `work_result_acceptances` and a matching `full` or `conditional` `rhythm_satisfactions` for the same original Work, Subject, Result and actor. This changes no Event or ordinary reporting writer.
- Companion draft [Noel PR #2362](https://github.com/optical-lift/noel-core-db/pull/2362) stages `10_care_actual_single_done_cutover_candidate.sql`: a replacement for the EXISTING farm domain Actual writer that removes direct Work/allocation Done and calls this one lifecycle transition. The physical domain still owns the meaning of weeded, acceptable/no-cut, partial and blocked; only accepted full/conditional results can become terminal Done. Historical replays do not fabricate a new signed event.
- PR #2362 includes `manual_care_single_done_cross_draft_rollback.sh` and `11_care_single_done_cross_draft_postconditions.sql` for a local disposable full-schema-clone composition check. **They have been committed, not executed as signed positive tests.** Each PR's Database Custody CI is source-only; it does not prove the two candidates compile together or work under real GoTrue sessions.
- Neither draft release package includes this integration as an approved release. PR #2362's old assembled `release_candidate.sql` explicitly remains held because its included `02` care writer still contains independent direct Done. The later replacement `10` must be applied atomically after the lifecycle source, once the cross-source gate passes. No production migration or grant changes.
- Mandatory gates: full existing-schema rollback compile and source postconditions; signed governor/connected worker/outsider/revoked/alternate-reader tests; care full/conditional/partial/blocked, replay and collision; Event, household and older original Work regressions; source-assigned Ledger completion projection; then **separately** root-admin-approved standing stewardship, bounded daily next-bed admission and live contextual Today/Work Focus before Anna's notebook can be called operational.
