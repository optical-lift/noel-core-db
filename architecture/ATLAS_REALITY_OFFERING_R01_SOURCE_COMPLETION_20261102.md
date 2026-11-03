# R01 — Atlas Reality Offering: owner-standing care → accepted Actual → one next Work

Status: **SOURCE-ONLY / HELD — NOT signed or released**. Date: 2026-11-02.
Owning source: Noel continuing original-Work candidate (#2362) with narrowly
reconciled standing owner campaign source (#2364), not a new task engine.
Target: existing Atlas My Work / Today / CanonicalWorkFocus, then Laundry and
Christmas through the same generic original Work and Result contracts.

## Bounded outcome
An active native Ledger root approves one source-bound winter stewardship visit
for an existing real bed or mowing route and a currently accepted connected
Person. The Work carries its original Subject and source Rule. The responsible
Person reports a typed physical Actual. One accepted terminal Result goes
through Noel #2368's universal one-Done lifecycle; then an approved campaign
may deliver only ONE next eligible original Work on the next owner-approved ISO workday, if that day exists within the campaign.
Partial/blocked results do not cause a new original. Accepted history survives
a failed successor attempt with an explicit needs-review receipt.

## Source integration completed in this branch
1. Base parent is Noel #2362 at `5984257962b37362d198fd94193af05c47525d8a`.
   The previously diverged Noel #2364 is NOT merged wholesale.
2. `16_native_standing_source_authority_extension_v1.sql` rebased from live
   guard `md5(prosrc)=1043ad551860196f1a13df25de9f8478`. Preserves
   `capability_root_authority_context_self_v1` for Ledger connection-direct
   responsibility, the earlier observed-source native-person path, and a new
   narrow accepted-Actual-only successor exception. The native exact-source
   resolver remained source-matched at `7570082f04024397227545e685a4c071`.
3. `19_owner_standing_visit_source_writer.sql`: approved first original,
   existing native scope, real Subject disclosure, date, season end, no old
   employee seat or fabricated weed pressure.
4. `20_owner_standing_candidate_preview.sql`: read-only per-rule candidate
   preview including disclosure obstacles; no Work creation.
5. `21_owner_standing_successor_authority.sql`: exact prior accepted physical
   Result, campaign, Person, Rule, Subject and next date verifier/selector.
6. `22_owner_standing_campaign_auto_advance.sql`: one-open-at-a-time bounded
   continuation, existing-source conflict denial, stable campaign identity.
7. `10_care_actual_single_done_cutover_candidate.sql`: after universal Done,
   invokes standing successor only for accepted terminal results; same-action
   replay may reconcile a missed successor; blocked/partial remain open.
8. The owner writer now requires a signed, sorted ISO weekday set for the
   campaign. `21_owner_standing_successor_authority.sql` contains a private,
   fail-closed workday resolver. The verifier and automatic successor use the
   SAME owner-approved days; a legacy hardcoded Sunday-skip is removed.
9. `r01_reality_offering_release_candidate.sql`: ONE ordered test-source
   transaction (not a migration), explicitly requiring the held Noel #2368
   universal Work lifecycle in a disposable schema first.
10. `r01_reality_offering_postconditions.sql`: private ACL, live Ledger root,
   old observed-source admission, canonical single Done and negative unsigned
   source checks. `manual_r01_reality_offering_rollback.sh` targets ONLY
   `127.0.0.1:54322` and always rolls back. Reproducible static source
   checks live at `tests/atlas-r01-standing-source.test.mjs`.

## Evidence and remaining release gates
- After exact current source reassembly, **38/38 in-memory static source
  assertions PASS**. These check retained native root authority, continuing
  Actor admission, unified Done, accepted-Actual-only successor, frozen and
  validated owner ISO workdays, explicit campaign cutoff, idempotence,
  source-bundle integrity and the local-only rollback runner.
- **NOT RUN:** PostgreSQL DDL compilation, rollback postconditions, live
  GoTrue-signed governor/connected worker/outsider/withdrawn grant tests,
  concurrent/double-click accepted Result → next Work, native Today/Work Focus
  desktop or iPhone, owner readback, or a real farm policy acceptance.
- The earlier #2362 source and sibling Noel #2368 lifecycle were held; their
  exact combined complete-dependency source must be staged in a disposable
  production-schema-shaped clone before the manual script can pass. The R01
  manual script deliberately refuses a clone missing the one-Done prerequisite.
- First production calibration still requires rooted current approval of
  exact winter service purpose, bounded daily capacity, workday/calendar rule,
  authorized connected Person and Subject disclosures. The candidate uses
  existing source rhythms and a bounded owner campaign; it **does not yet
  install the reusable versioned Foundry-governed Rulebook** or prove the
  end-to-end UI. Do not claim the full universal release on this source slice.
- Existing open U-Pick mowing Work and conflicting legacy task/Work state must
  be reconciled with source evidence, not duplicated; no real user Work or
  source grant is changed here. The legacy rhythm cutover must be proven not
  to create duplicate tasks or recurring timer churn.

## Next bounded execution
On the owner's RiverSong isolated production-shaped clone: first establish
the reviewed sibling universal Done source, run the R01 rollback package and
postconditions, fix exact failing SQL or source signature, then execute an
independent signed governor → Anna-like connected Person → outsider test
including accepted/full/partial/blocked Actual and exact next-original readback.
Only after a verified source journey should the existing Atlas Today and Work
Focus care UI drafts be reconciled with current deployed app main.

## Custody
No production migrations, direct Supabase writes, real farm Work, permissions,
release deployment, new infrastructure, runner changes or paid branches.
No changes to Atlas app main. Final release remains separate authorization.

## Verified live-source caveats to resolve before real Elm use
- The existing U-Pick mowing rhythm rule still contains stale equipment
  metadata saying `Riding mower`. Do NOT show this as a current instruction;
  the verified push-mower correction must be source-reconciled first.
- R01's **one-outstanding-Work** campaign capacity is deliberately narrow.
  A configurable per-day capacity, full Foundry Rulebook adoption, UI-based
  governor workday approval and operational signed actor proof are NOT shipped.
- A successful signed Actual cannot itself prove that the next Work reached
  Anna's Today; separate actual signed My Work/Today/browser readback remains
  mandatory.

## November 2: actual RiverSong and protected-clone verification
- Existing `RiverSong` self-hosted runner at `optical-lift/atlas` with label
  `atlas-verifier` verified working, **without modifying runner registration**.
  Carrier workflow in held Atlas branch
  `r01/riversong-standing-care-rollback-20261102`.
- [Atlas RiverSong run #41573094405](https://github.com/optical-lift/atlas/actions/runs/41573094405):
  local PG17 `noel_schema_clone`, socket `55432` and exact PGDATA
  confirmed, exact Noel SHA checkout succeeded, **8/8 committed Node
  source tests passed**. SQL failed closed: clone missing
  `atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)`.
  One SQL transaction automatically rolled back; no live data mutation.
- [Atlas RiverSong run #41573335081](https://github.com/optical-lift/atlas/actions/runs/41573335081):
  test-only restoration of the precisely catalogued current native
  source was attempted inside ROLLBACK, then failed safely because the
  local clone lacks required `ledger.booking_requests` and/or
  `ledger.booking_offerings` tables. No fictional stand-ins were created.
  That clone is **not** sufficient for full-source R01 proof.
- Previously [Noel protected signed-clone #40892657460](https://github.com/optical-lift/noel-core-db/actions/runs/40892657460)
  had passed authentic owner/worker/outsider observed-source admission,
  native Ledger relevance, original My Work/Today projection, duplicate
  and withheld Subject tests at source SHA `5984257962b37362d198fd94193af05c47525d8a`.
  This does **not** prove owner-standing successor after a physical Actual.
- Full production-shaped disposable clone rerun initiated via
  [Noel owner validation request #2454](https://github.com/optical-lift/noel-core-db/issues/2454)
  and [protected run #41573867067](https://github.com/optical-lift/noel-core-db/actions/runs/41573867067).
  Its first clone-only candidate SHA was
  `ea951fe4279e9b8f5fbacb055ae7445f4dd17648`: the full
  production-shaped PostgreSQL schema accepted the new owner visit,
  ISO workdays, source Done/Actual and successor DDL, and all structural
  postconditions passed. **Signed run failed**, correctly, at missing
  public `connected_person_disclosed_standing_rhythms_self_api_v1`
  (PostgREST PGRST202, not a valid denial). This is an unstaged held
  sibling-source dependency, not proof of an R01 signed successor.
- No merge to production source, Person grants, real farm data mutations
  or Atlas app deployments. After clone SQL compatibility, the mandatory
  R01 signed accepted Actual → next Work → worker Today/owner Ledger
  journey is STILL OPEN until separately proven. The reader has now been
  reused byte-for-byte from held Noel #2385 in
  `23_connected_person_disclosed_standing_rhythms_v1.sql`, assembled into
  the R01 source package, and staged in a refreshed non-releasable clone
  canary at SHA `6fe09b47c7558787a1eb048daffc9c0ea560b032`.
  [Owner validation issue #2455](https://github.com/optical-lift/noel-core-db/issues/2455)
  starts [signed-clone retest #41574368737](https://github.com/optical-lift/noel-core-db/actions/runs/41574368737).
  The outcome is pending; do not infer success. Do not call R01 complete
  merely because earlier observed-source admission is green.

## R01 validation outcome — source and existing signed journey verified
- [Atlas RiverSong source-only #41575070078](https://github.com/optical-lift/atlas/actions/runs/41575070078):
  **10/10 committed Node source regressions PASS**, pinned at Noel source
  commit `2418dc7196a14682f017581495226ff6644d02cd`. Includes new
  signed public governor standing-visit membrane, exact private ACL,
  native rhythm-disclosure reader, approved ISO workdays and Next-Work
  source guards. This is source-only, not a SQL or human acceptance.
- [Noel full-schema protected clone #41574368737](https://github.com/optical-lift/noel-core-db/actions/runs/41574368737):
  **PASS** for non-releasable canary SHA
  `6fe09b47c7558787a1eb048daffc9c0ea560b032`; checked the actual
  artifact. R01 SQL compiled on the complete production-shaped clone,
  all postconditions passed, and **four real independent GoTrue user
  sessions** exercised signed governor, worker, outsider and withheld
  Subject enforcement. Passing original Work/Actual/one-Done, observed-
  source next Work, repeat denial, Person My Work/Today, hold/revocation.
  Baseline Atlas lint 14 errors; candidate 14; **zero newly introduced**.
- The above signed acceptance follows the **observed-source** model in
  the existing validator. It DOES NOT exercise the newly introduced
  `public.owner_establish_standing_continuing_care_work_self_api_v1`,
  nor confirm that a first owner-standing Work's worker Actual
  autonomously releases the next disclosed Subject. The governor
  public membrane and its stricter postconditions were added AFTER
  the pinned canary SHA above. Updated held canary head after source
  reorder: `a75693752e2ca96775abe6312d986afc012fb380`. Its own
  SQL and signed owner behavior are **UNTESTED**; no false PASS.
- Next actual signed test must initialize at least TWO independent
  fictional rhythm Subjects under the same approved campaign,
  with separate exact Subject grants and different cadence rules.
  The governor must call the real `public.owner_establish_standing_continuing_care_work_self_api_v1`
  over bearer HTTP with an explicit nonempty approved ISO workday set.
  Worker and outsider must fail that same endpoint with source denial,
  not PGRST202. Worker observes/records a true qualifying first-party
  Actual and causes the single universal Done. One successor Work
  should become active only if eligible and inside the frozen
  approved-days/end-date window; it must remain the original Work
  in signed My Work/Today and Ledger with correct Plan/Result.
  Verify duplicate/retry, disallowed workday, held/revoked grant,
  partial, blocked, overlapping older Work, explicit next-work
  review when the lawful successor fails, and exact campaign close.
- This is a new bounded **test infrastructure + signed continuation
  proof** round. Do not try to claim it by replaying the earlier signed
  observed-source test, or by a raw SQL auth.uid() impersonation.
  Neither proposed source nor app is production enabled.
