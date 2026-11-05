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
