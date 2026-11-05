# UNI-OPS-01 Actual-first P1 — assigned activity to existing care Actual (HELD)

**Status:** Source-only candidate, no migration, release, application UI, credential, Work or Actual created. Stack is based on Noel U2E draft #2486. This is not a production source grant.
**Authority:** November 4 owner decisions 1B/2D/3D/4C/5A/6A/7A; exceptions 1B/2C belong to P2; U2E prospective 1C/2C/3C preserved.
**Canonical owner:** Noel for Work, Person, Subject, Result, Actual, state and permissions. Atlas remains the presentation/one-sentence capture layer.

## What this increment does
The authenticated original worker chooses one existing manual activity record and one exact existing assigned canonical Work ID. The worker also explicitly attests a typed care result and observed condition. This does not infer a physical state from sentence text.

Noel checks the existing unretracted first-party evidence, current farm membership and canonical Person, prior establishment of Work and specific responsible allocation, exact farm/Subject relationship, and the native care Result writer. The existing activity UUID serves as the action key. Only a source-accepted physical Actual can produce an immutable one-to-one evidence/Result link; no second Work or Actual store is introduced.

The new evidence-link table is private, RLS protected and append-only. Underlying Result receipts must explicitly say no new Work and no Clock admission; otherwise the transaction fails. Campaign-linked originals with the old Result-driven successor path are denied until P3. A manual log by itself still changes no operational state.

## Existing source interfaces
- Evidence: Noel migration 20260829172226_worker_manual_activity_log_v1.sql, with atlas.field_logs source worker_manual_log.
- Original: existing atlas.work_items, work_allocations, work_item_context_links, rhythm_state, disclosed Ledger source.
- Result: held R01/R02 atlas.record_continuing_care_actual_self_api_v1, which validates real typed physical effects and stores accepted work_execution_results/work_result_acceptances.
- Proposed signed RPC: public.recognize_assigned_care_activity_self_api_v1(activity_log_id, work_item_id, actual_kind, condition_after). The private source function rechecks all identity and scope.
- No general text-to-Work matching, retrospective governor adjudication, Household/Event generalization or new scheduler.

## Native schema-only reconciliation / RiverSong verification (2026-11-04)

Held file `05_exact_native_ledger_source_schema_reconciliation_held.sql` preserves the native Ledger verifier's two exact booking source-FK predicates while refusing to return any verified source if their historical booking relations are absent. It does not create booking tables, synthesize proof, weaken source attribution, or alter the real relevance trigger. It revokes authenticated helper execution. This is a source-owned held candidate, **not a production patch or release grant**.

Fresh PG17 + native GoTrue/PostgREST RiverSong [#41965499066](https://github.com/optical-lift/atlas/actions/runs/41965499066), [#41965643053](https://github.com/optical-lift/atlas/actions/runs/41965643053), and diagnostic [#41966117584](https://github.com/optical-lift/atlas/actions/runs/41966117584) confirmed P1/R01/lifecycle compilation, genuine signed denied no-Work requests, anonymous denial, and fail-closed no-booking-source verification. All three fresh databases and services were cleaned, with retained clone read-only.

**Signed positive P1 remains untested.** The older C1 fictional fixture contains unrelated Household rows triggering missing `atlas.ensure_household_care_policy_v1(uuid,timestamptz)`. After those unrelated rows were excluded in scratch, its garden care fixture hit another missing helper: `atlas.is_retired_growing_object_v1(text)`. The persisted `atlas.guard_retired_object_rhythm_binding_v1`, `atlas.guard_retired_object_rhythm_state_v1`, and `atlas.guard_retired_object_task_v1` call that nonexistent helper. This is an unresolved canonical source-history/schema seam. Do **not** install a fake allow/deny helper or bypass those guards to force a test pass.

**Next one bounded task:** reconcile the exact original retirement helper source and its migration/adjudicated retirement in Noel, then stage a genuinely source-authorized Person/Ledger/Subject care-original fixture without unrelated legacy Household setup. Only afterward run signed positive typed Result and physical state/Need/evidence readback, replay, mismatch, withdrawal and concurrency tests. P2–P5 and production stay held.

## 2026-11-05 source-baseline reconciliation — authoritative P1 gate (HELD)

**This supersedes the older fixture-specific next step above, without erasing its diagnostic history.** Noel's live `atlas.is_retired_growing_object_v1(text)` definition was recovered verbatim from current read-only catalog metadata (held 06). Signed native Ledger principal → worker standing offer/acceptance, and two separate owner-granted Bed 3 disclosures (identity and condition), **passed** on [RiverSong #42064109341](https://github.com/optical-lift/atlas/actions/runs/42064109341). These calls created no Work. This is real signed consent/disclosure evidence, not Result acceptance.

The signed governor-observed original issuer then encountered a series of **retained test-clone omissions**, not failed physical eligibility: current care strategy state `atlas.object_state`, outstanding individual Work offers, and plan-responsibility reconciliation and worker-day carrier source. Held source files 07–16 preserve selected read-only live definitions **only in disposable scratch**; they are not migration approvals or a production-equivalent restored baseline. [Signed Work probe #42069027675](https://github.com/optical-lift/atlas/actions/runs/42069027675) **FAILED** before original Work issuance at the complete private plan-carrier dependency preflight. The worker evidence-to-typed-Result code was not reached.

The authoritative [**17_current_live_carrier_schema_parity_manifest_held.json**](17_current_live_carrier_schema_parity_manifest_held.json) captures a single **19-object** live catalog cohort (five tables, fourteen functions), including current callable definition MD5 fingerprints and source table column/constraint/trigger counts. It contains no data, credentials or guessed permissions. On a verified read-only retained clone, [RiverSong inventory #42070951792](https://github.com/optical-lift/atlas/actions/runs/42070951792) found all nine worker-day/execution carrier trigger functions absent. The [pinned source parity audit #42071869279](https://github.com/optical-lift/atlas/actions/runs/42071869279) **PASSED AS AN AUDIT** with **0/19 matched; 19/19 missing** and a clear `P1_SIGNED_POSITIVE_SOURCE_BASELINE=BLOCKED`. A green inventory job is not a green P1 physical acceptance test.

**Required next one bounded outcome:** prepare a **current, source-authorized, schema-only Noel verification baseline as a unit** (not additional synthetic table/function stubs), into a newly disposable PostgreSQL test database. The retained RiverSong clone remains strictly read-only and must not be patched in place; no real Person, Work or farm data may be copied. Validate table/FK/index/trigger/RLS/ACL parity, canonical source signatures and applicable version/release hold **before** invoking the genuine signed owner Work issuer, then worker first-party activity and typed Result. A current schema-only catalog **metadata manifest alone is not a dump or proof of authority parity**, and this 19-object cohort is a necessary, not exhaustive, acceptance baseline. If the source-equivalent database cannot be obtained, stop and report BLOCKED rather than bypass safety or repeatedly graft unrelated live SQL.

Positive owner Work issuance, worker typed Result acceptance, replay, wrong actor, withdrawal, conflicting evidence and concurrent recognition remain **OPEN**; P2–P5 and all production/merge/release gates remain **HELD**. The authoritative Atlas completion register owns evidence receipts and next action.

## Dependencies and tests
Compose only on a **verified disposable PostgreSQL clone**: migration baseline, exact pinned R01/R02 care Result source and lifecycle, current canonical Work/Person/disclosure, U1A/U1B/U2C/U2E dependencies, then 01 source SQL and 02 postconditions within one transaction ending ROLLBACK.

03_local_rollback_source_check.sh requires an explicit disposable-clone confirmation and a **local** PostgreSQL connection URI. It applies candidate plus postconditions inside BEGIN/ROLLBACK and cannot be taken as signed acceptance. Use only on a local isolated clone, not a production proxy. The local URI must be supplied by the actual RiverSong clone operator; no port or credentials are assumed.

For an already assembled safe local clone, with the branch checked out, the command is:

P1_DISPOSABLE_CONFIRM=ROLLBACK_ONLY P1_DISPOSABLE_PGURI='host=localhost port=YOUR_ISOLATED_PORT dbname=YOUR_CLONE user=YOUR_LOCAL_USER' bash candidates/atlas_actual_first_p1_assigned_care_activity_v1/03_local_rollback_source_check.sh

The shell check refuses remote-looking connection strings but cannot detect a deliberately proxied production database. Independently verify the clone before running.

Source tests are in tests/atlas-actual-first-p1-source.test.mjs. Those checks are structural, not a PostgreSQL, signed-user, concurrency, real Result, browser or release proof.

## Mandatory signed acceptance after compilation
- Correct signed assigned Person and unretracted exact activity + typed actual: one accepted Result on the same original, one immutable evidence link, warranted domain state and Need change, no successor Work.
- Wrong/withdrawn Person; wrong Subject/farm; withheld Work; changed Rule; conflicting or duplicate evidence: no mutation or information leak.
- A report predating establishment/assignment: deny rather than fabricate prior authority.
- Partial/blocked: preserve their nonterminal meaning, no guessed condition.
- Concurrent recognition attempts against one log/another Work: at most one link and one accepted original Result.
- Campaign-linked Result attempt: stop before triggering the old auto-advance path.
- Raw manual evidence insert: no Work/Need/Clock mutation.

## Release hold and next gates
Noel current main and the stacked U2E branch have diverged; exact dependencies must be reconciled. The older R02 Result writer can create another original from a standing-campaign Actual. P1 blocks that route in this narrow pilot, but **P3 must remove automatic continuation before any broader release**. Neither source presence nor 14 static checks can replace a disposable PG compilation and real signed actor tests.

P2 retrospective governor recognition, P3 no-successor cutover, P4 one-sentence Atlas notebook and P5 independent Household/Event acceptance remain separate. Record exact results in the existing Atlas completion register. Do not merge, deploy, alter permissions, production, CI, Vercel or credentials on the strength of this held source.
