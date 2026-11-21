# UNI-OPS-01 — completion-only / Actual-first / campaign source compatibility gate

**Date:** 2026-11-06 · **State:** SOURCE-ONLY AUDIT / INTEGRATED RELEASE HELD · **Owner:** Noel (#2505) · **Consumer:** Atlas (#532).

## One bounded outcome and protected scope

Determine whether the already signed **native Person-authorized original Work completion-only** package is compatible at source level with (a) assigned-care P1 Activity → typed Actual and (b) the held U1/U2 Rulebook, offer, campaign and original Work path. Preserve the original Work identity, accepted Result and at-most-one terminal Done. Explicitly enforce November 4 owner decision **6A: accepted Actual may qualify Need/state but must never automatically issue another Work/campaign**.

**Inside this increment:** immutable Git blob comparison, a read-only executable source-boundary script and this review receipt. **Outside:** alteration of candidate SQL, historical cancellation, P2 retrospective issuance, P3 cutover, SQL migrations, Source/RLS/ACL/grants, production data/people, authenticated test runner or CI workflow changes, PR merges, deployments, real Anna/Elm acceptance.

## Exact mainline and source identities

At read-only audit: Noel `main` **c4ef5795bb459fe48f17708749296b62fc1c28f4**; Atlas `main` **c3a20b33175707d7355ab3d5462ebf49cba51985**. These do not imply the held candidates have merged.

| Stage / owner | Pinned SQL Git blob SHA-1 | Held source |
|---|---|---|
| Native-only universal completion packet, Noel #2522 | `0e7c8581e6656b218bdc1ff2c13152201e3e03f5` | `candidates/atlas_native_person_completion_release_packet_v1/candidate.sql` |
| Native-only L2 transition, #2522 | `3178e11863f1c6de89e07724c3b209923fd825d3` | `candidates/atlas_native_person_completion_only_v1/06_single_transition_native_person_completion_only_held.sql` |
| P1 assigned Activity recognizer, Noel #2487 | `476e85b1e6f46d7ac996dce9ea0e51b89c50f28c` | `candidates/atlas_actual_first_p1_assigned_care_activity_v1/01_assigned_activity_recognition_held.sql` |
| C1 typed care Actual + single Done, Noel #2362 | `967456ae34a305a59d663a73f90f9070ef74f1ba` | `candidates/atlas_universal_continuing_original_work_v1/10_care_actual_single_done_cutover_candidate.sql` |
| U2C original writer accept-first guard, Noel #2485 | `4413d84b042a357567a2334cddccc859650c41dc` | `candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/02_native_original_writer_acceptance_guard_held.sql` |
| U2E campaign, Noel #2486 | `a558a8bd09e9e470ec82619193e3162b6818f0f7` | `candidates/atlas_uni_ops_c_u2e_seasonal_scheduler_mandate_v1/01_pending_campaign_root_source_held.sql` |
| U2E old-route cutover, Noel #2486 | `4fdc9cf56cefe6c70ec5af24ec43f7a5e8a72015` | `candidates/atlas_uni_ops_c_u2e_seasonal_scheduler_mandate_v1/02_close_ungoverned_offer_and_finalizer_held.sql` |

The existing `#2522` manifest independently verifies seven source SQL blocks in its packet; the seven inputs above are **cross-PR boundaries**, not a competing SQL release assembly. Their Git blobs were read through the connected GitHub repository at the held refs on November 6, and **13 of 13 static checks passed** (one pinned-input identity check plus 12 structural source-boundary assertions).

### Reproducible read-only source comparison

New script: [verify-atlas-uni-ops-source-boundary-20261106.mjs](../scripts/verify-atlas-uni-ops-source-boundary-20261106.mjs). Run `node scripts/verify-atlas-uni-ops-source-boundary-20261106.mjs` with **seven separately checked-out local SQL paths** in the precise order listed above. Each path must match its SHA-1 Git *blob*, not a file display title. The script reads only and fails closed on drift. It has **not yet run on RiverSong or as a repository Node test**; the matching comparison logic was executed against actual fetched contents in the review session. Do not cite a source-only or syntax check as a PG/GoTrue pass.

## Source compatibility verdict: held boundary, not a safe composite

1. **Completion-only #2522 does one thing:** installs one private `atlas.apply_work_lifecycle_transition_internal_v1` for *complete*, maintains native responsible Person, preserves existing connected-Person and shared Event original-Work receipt cutovers, and excludes historic cancellation/review 16–22. It deliberately **does not install** P1, the care writer, the Rulebook or a background issuer.
2. **P1 #2487 supports a narrower source path:** a first-party recorded worker Activity must predate neither the canonical original nor its *specific assigned responsibility*; P1 rechecks current Person, native source, relationship and typed care evidence, then invokes `atlas.record_continuing_care_actual_self_api_v1`. The final C1 care writer invokes the same private universal Done operation with an accepted physical Result. Static interfaces align for one already-existing, specifically assigned **noncampaign** care original. No new Work/Clock receipt may be missing.
3. **Material blocker, confirmed from exact source:** U2C's original Work writer stamps `sourceStandingCampaignId`. P1 expressly rejects any Work with that field, or `sourceAdmissionMode=owner_standing_successor_v1`, until **P3 no-automatic-successor source cutover**. This denial is a safety requirement, **not** permission to strip campaign metadata or relax P1. Therefore **a U2E-accepted campaign original is not yet eligible for the P1 one-sentence recognition path**, even after a valid issuer exists.
4. **Separate issuer blocker:** U2E supports a root-approved ≤120-calendar-day, single-offer/single-original campaign and closes older public noncampaign entrypoints in held SQL. Its real scheduler carrier is `unbound`; the current root-finalization operation cannot impersonate an independently authorized automated issuer. No source-verified unattended original exists. No campaign auto-renews from Done.
5. **Additional compatibility unknowns:** U1A/U1B precedence and Subject identity, source-positive first issuer, cross-writer capacity lock (≤3), every old direct writer and public RPC ACL, populated baseline lock/performance, old Event vs new Result writers, alternate readers and non-farm second-domain behavior have **not** been accepted together. A source-text match is not a cross-version concurrency test.

## Protected signed evidence versus next runtime test

- **Existing bounded positive:** Noel [completion-only run #42155239457](https://github.com/optical-lift/noel-core-db/actions/runs/42155239457) passed current packet signed native Person original Work and preexisting root-shared Event Done/replay/denials on isolated production-schema clone. No general current-source Person concurrency or old-writer full integration was established.
- **Separate P1 positive:** [P1 signed run #42105399414](https://github.com/optical-lift/noel-core-db/actions/runs/42105399414) passed assigned physical care Actual with a larger **older diagnostic composite**. Noel #2487's custody audit specifically says this cannot be released as a canonical migration and does **not** prove a composition with #2522 or U2E.
- **Proposed next disposable acceptance, NOT YET EXECUTED:** use an explicitly selected exact current-schema Noel-owned source composition of one native L1/L2, C1 qualified Result and P1. Prove signed assigned noncampaign Work → Activity → one accepted Result → one Done, replay (same and different action), two concurrent actors, unauthorized/revoked/other-Ledger denials, no duplicate original/Result or new Clock/Work, legacy self-adoption denial and preexisting shared Event regression. Separately assert campaign-linked original + P1 produces a **correct denial**, preserving evidence and original; do not demand a false positive. Test old direct writers / one authority through the cutover, not only the new RPC. Check fresh clone schema, populated baseline, RLS/ACL, work count, branch exactness, postconditions, cleanup and signed receipts.
- **Separate U1/U2/P3 gate:** before campaign P1 positive can be attempted, source-own the independently authorized issuer and P3 no-auto-successor cutover, then test consent, revocation, one-offer-one-original, cross-writer capacity and two-domain regression. No change to current live Source is implied.

## Next bounded step and register accounting

**Next action:** Noel #2505 source owner selects the minimal current noncampaign C1/P1 + #2522 disposable composition and validates its exact native writer dependencies and test carrier. If running this composition needs a new CI authorization or source permissions, **stop and obtain that authority** instead of altering protected workflows. The existing #2522 package and its signed tests must not be relabeled a completed integrated release. Track U1/U2C/U2E/P3 behind the separately held source boundary and return to the U1→U2→U3→U4 human operating journey after the compatibility blocker is addressed.

**Disposition:** 7 immutable SQL blobs verified; 13/13 bounded static checks PASS; source-contract mismatch explicitly identified; **integrated PG/GoTrue acceptance NOT TESTED; release HELD**. Historical cancellation remains held; all 18 existing Atlas completion obligations remain open under their existing owners.

## November 6 live catalog corroboration (read-only, **not** a test execution)

A fresh `SELECT` of `to_regclass` / `to_regprocedure` signatures in the existing production Supabase project confirmed **present**: `atlas.current_person_id_v1()`. Confirmed **absent**: `atlas.work_lifecycle_events_v1`, `atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)`, `atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)`, `atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)`, `public.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)`, `atlas.assigned_care_activity_recognition_links_v1`, both `atlas.governed_rulebook_*_v1` tables, and the held historical review table. Only these exact named catalog objects/signatures were checked; this is not an exhaustive installed-function or migration comparison. This read performed no data or permission mutation. A published signed clone run remains test evidence only.
