# Titus Build 1F — source-issued sample classroom invitation, acceptance and withdrawal

**Date:** November 4, 2026  
**Owner:** Noel source custody. **Base:** [Build 1E PR #2470](https://github.com/optical-lift/noel-core-db/pull/2470).  
**Status:** Private source-only candidate; neither source nor API is deployed.

## One bounded outcome

Close the biggest gap between the working fictional Titus classroom and an actual shared two-Person learning record: **how the right learner and the right teacher become authorized to exchange the original work**. This increment uses existing Atlas Teaching Offering/Enrollment and root-principal authority, and it requires independent signed acceptance instead of treating an enrollment or a UI role switch as consent.

## Flow

1. The signed **current canonical principal** with active root governing authority to the Offering's Ledger offers exactly one teacher seat and one learner seat for one fixture-only Titus classroom. The Offering and Course must be active and Teaching capability in force. A different organization/Offering, teacher profile or room creator cannot issue the assignment.
2. The named **teacher**, in their own signed current Person session, explicitly accepts the teacher appointment. The teacher still cannot read another Person's response until the learner consents.
3. The named **learner**, already actively enrolled in that exact Atlas Offering, explicitly accepts participation and names the already-accepted teacher who may read the response. The teacher cannot be switched implicitly.
4. Every source `authorize`, `read` and `append` call rechecks active assignment, exact immutable offered+accepted receipts, current root authority/Teaching Offering, active learner Enrollment, and named teacher consent. The existing event-root writer still independently defaults to **false**.
5. A learner can withdraw in their own verified session. No current learner read/write or teacher disclosure of their response survives that withdrawal; durable source original events remain immutable for proper custody.

## Source artifacts

- `candidate.sql`: private, RLS-closed immutable Offering binding and append-only offer/accept/withdraw originals; signed source-only issue and accept functions; a source-defined replacement of `titus.classroom_pilot_assignment_issued_v1` using those immutable originals, current Ledger authority and named reviewer consent. The existing `titus.classroom_pilot_participation_v1` serves current state but cannot alone authorize an original.
- `fixture_atlas_teaching.sql`: **disposable only** fake principals, active source Offering, active enrollment, Teaching activation and authority functions. Fake GUC identities from earlier fixture are **not** genuine GoTrue.
- `postconditions.sql`: negative tests for non-governor offer, wrong Person acceptance, missing explicit learner acceptance, premature teacher read, bad classroom; positive test for two distinct accepted persons, source authorization, one persisted original visible to teacher; withdrawal denying both and preserving the physical original; source writer gate restored false.
- `scripts/test-titus-classroom-issuance-riversong-pg17.sh`: fresh private Unix-socket PostgreSQL 17 cluster on RiverSong port `55441`, verifying exact data directory/no TCP, inherited test SQL at pinned SHA, fixture only, cleanup trap, no protected Atlas clone (`55432`) or production connection.

## Protected scope

No real person, student, historical Formation edition, school, institution, production grant, production migration or authentic GoTrue session is created. The candidate does **not** modify Atlas Teaching tables or principal authority. Test fixtures synthesize them in an isolated PostgreSQL cluster. There is no real appointment or actual disclosure permission until source governance and authenticated production-shaped tests independently approve deployment.

No Titus Next route, approved visual Preview v4, university curriculum, deployment or production endpoint changes.

## Acceptance register

| Gate | State |
| --- | --- |
| Source read/append event carrier with shared originals | PASS, [RiverSong Titus carrier #41873256390](https://github.com/optical-lift/titus/actions/runs/41873256390) |
| Signed current Person issuer using actual Atlas root/Teaching source names | Source coded; signed-session fixture only |
| Principal offer → teacher self-accept → learner named consent | **PASS, fictional PG17** [RiverSong #41884149777](https://github.com/optical-lift/titus/actions/runs/41884149777) at exact Noel source SHA `77a1e0e40572015e67bca559f0358e74c4868ffb` |
| Withdrawal shuts learner and reviewer access | **PASS, fictional PG17**, same exact run/SHA |
| Immutable event/assignment history, private RLS tables | **PASS, fictional PG17**, same exact run/SHA; no browser role table privileges |
| Real signer/issuer tests from two actual GoTrue accounts | NOT DONE |
| Independent writer custody, live source permissions/release | NOT DONE |
| Two-person deployed Titus classroom UI | NOT DONE |

**Next after runtime proof:** complete the governed replacement for the still-hard-false *event writer* gate and demonstrate two genuine self-authenticated accounts in an isolated source-shaped test. Only then enable the actual Titus classroom GET/POST route and switch the approved UI from its browser-local demo store to server projections. Do not merge the whole draft stack merely because this sample fixture works.


## 2026-11-04 verification closeout — exact code SHA

The independent Titus repository RiverSong carrier [#41884149777](https://github.com/optical-lift/titus/actions/runs/41884149777) **SUCCESS**, running pinned Noel SHA `77a1e0e40572015e67bca559f0358e74c4868ffb` through three fresh, private Unix-socket PostgreSQL 17 clusters: membership on `55437`, immutable read/append on `55439`, and this issuer on `55441`. The protected Atlas clone `55432` was untouched. The logs specifically confirm principal offer, teacher self-acceptance, learner named-teacher acceptance, one shared original, subsequent withdrawal denying both parties, and the independent event writer gate restored **false**.

Initial issuer tests failed because this independent fixture omitted the `class` and `homework` part registry that the older read/append fixture had seeded in its own postconditions. Separate-statement permission tests established the denial persisted after acceptance; the disposable root probe verified authentic fixture issuance was `true`, accepted receipts and active enrollment existed, and permitted parts were missing. The fix seeds only those two fixture parts, without weakening any production candidate source authorization. Diagnostic instrumentation was removed after identification.

**Precisely closed:** source-only sample classroom Build 1F synthetic PG17 acceptance. **Not closed:** real GoTrue/Person approval issuance, real rights-cleared learner/teacher seats, production source migration/grants, independent write-gate release, or deployed Titus two-person classroom. Keep PR #2471 draft and issue #2461 open; no merge, deployment, data mutation or real classroom access.
