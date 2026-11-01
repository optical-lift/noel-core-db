# Carry Build 1 — v3 database-enforced adoption: acceptance contract

Status: **held source only**. Existing Us Carry v1 (`20261027204404`) and
dated-event v2 (`20261027222504`) are unreleased. No production SQL,
Atlas objects, new identities, or private financial data are involved.

## Bounded outcome

After v3, the private service role MUST be unable to create financial
expectation revisions or lines independently or call
`us.carry_append_event_v1` directly to seal a preassembled draft.
One owner-scoped, narrow event-derived adoption function must reconstruct
the exact dated candidate from an attested adopted baseline and the current
immutable Carry event cutoff in a single transaction.

The tested Python writer in Us PR #1 **does not meet this database privilege
postcondition yet**, even though its separate-connection adoption race passed
on RiverSong. Do not substitute a Python lock or a session-settable GUC for
the database privilege boundary.

## Existing authority to preserve

- Supabase Auth `get_user(token)` verified at the trusted Us server;
  no request-supplied owner ID and no user_metadata ownership.
- Only the private Us database schema; all direct `anon` /
  `authenticated` table and function exposure remains revoked.
- Existing adopted revision remains append-only and unchanged.
- Existing financial source/case stream identity and history remain intact.
- Candidate is uniquely keyed by `(period_month, line_key)`, with
  plan-window, scope, exact-decimal and evidence-class constraints.

## SQL postconditions for v3

1. `service_role` lacks INSERT on both
   `us.financial_expectation_revisions` and
   `us.financial_expectation_lines`.
2. `service_role` lacks direct EXECUTE on the legacy unrestricted
   `us.carry_append_event_v1` entrypoint. Its replacement ordinary
   private event append path cannot accept `REVISION_SEALED`.
3. A dedicated narrow v3 function is the only service-executable
   writer for adoption. It checks exact owner and stream, locks the
   stream/plan, recomputes the original baseline fingerprint, reads
   every dated financial event in order through the expected cutoff,
   materializes all affected AND unaffected monthly lines, and seals
   the new revision atomically. No caller-supplied line array or digest
   counts as authorization.
4. Same approval idempotency key and exact event cutoff replay the
   same adopted receipt; a changed cutoff or payload is denied.
5. A competing new action with stale cutoff is denied, and two
   simultaneous valid approvals create at most one new revision.
6. Failure anywhere rolls back the draft revision, lines, and seal
   together. Direct inserts after adoption remain impossible.
7. Baseline/source provenance and the prior revision's history remain
   byte-equivalent after adoption. Non-additive balances are not summed.
8. A usable authenticated Us reader and reviewer must show the exact
   forecast line values that match the signed preview digest before
   allowing an approval. The server rechecks digest under lock.
9. Genuine signed independent GoTrue owner/outsider sessions must
   demonstrate authorized use and unauthorized non-discovery through
   the Us HTTP endpoint, not merely mocked tokens or SQL role grants.
10. No migration release without dependency-complete disposable clone
    tests, source custody CI, and separate protected authorization.

## Release / source order

1. Original private finance (already live).
2. Carry v1 (generated and source-merged, **not live**).
3. Dated-event v2 (generated draft PR #2345, **not live**).
4. New v3 (not yet generated or tested) — only when complete.

An attempted broad v3 database-function source submission was blocked by
the connected code-hosting safety check. That is not a passing SQL build.
Keep this acceptance gate explicitly open; do not weaken permissions or
invent a positive test receipt to close it.

## Verified precursor

- RiverSong automatic run #41216770910:
  55 Python tests and independent PostgreSQL approval race, unchanged
  adopted baseline, owner-denied candidate and full cleanup.
- Further Us HTTP/preview-digest work is on the active Us draft branch
  and must be verified against its latest SHA before being called green.

## 2026-11-01 held increment A — privilege floor proven, not releasable alone

- Owned source: `privilege_floor_candidate.sql` and `privilege_floor_postconditions.sql` in this existing v3 candidate. Dependency gate requires original finance + Carry v1 + dated v2; no new migrations were generated.
- [RiverSong exact-source PostgreSQL run #41312365493](https://github.com/optical-lift/us/actions/runs/41312365493) **SUCCESS**, using source commit `7be38cfeae1e7b24d1d918f5e68573332bc593ce` and dedicated `us-carry-verifier`.
- Test first observed the expected permission failure on the v1/v2 fixture, then applied held floor to a fresh localhost-only PostgreSQL instance and proved actual `SET LOCAL ROLE service_role` revision INSERT denial, line INSERT denial, legacy `carry_append_event_v1` EXECUTE denial and preserved review SELECT. No real financial users or data, no production/Atlas write.
- Protected scope: keep live v1/v2, existing Us private FastAPI runtime and Atlas unchanged. The current Python adoption writer would fail after this floor is applied without a new narrow SQL writer; DO NOT release the floor independently.
- Next unfinished dependency: usable narrow owner-checked read and ordinary-event entrypoints, then sole event-derived SQL adoption/review under lock, complete negative/concurrency regression and separate protected release gate. Do not mark v3 complete on this passing subtest.

## 2026-11-01 held increment B — ordinary-event replacement proven

- Bounded source: `ordinary_event_candidate.sql` plus `ordinary_event_postconditions.sql`; depends on the A privilege floor and unchanged original Finance/v1/v2.
- [RiverSong run #41312579078](https://github.com/optical-lift/us/actions/runs/41312579078) **SUCCESS** against Noel exact source `14320c57535dfe639aae2eb128ed41ce52634142` using a disposable loopback-only native PostgreSQL instance. It reran A's red-before/green-after tests, then called the new SECURITY DEFINER ordinary-event writer as actual `service_role`, proved authorized CASE_OPENED, identical-key idempotency, wrong-owner denial, REVISION_SEALED denial, no rejected-event mutation, and no direct v1 execution grant. No actual users or financial values entered fixtures.
- The only trusted caller is the Us backend after it validates the bearer with GoTrue; `p_owner_auth_user_id` is NOT a browser-supplied authority token. The database checks the supplied verified identity against the exact stream owner. The private HTTP adapter has **not** yet been switched to this entrypoint.
- Increment B is not the derived revision writer, owner-scoped private history reader, complete end-to-end v3 HTTP acceptance or production release. Do not deploy A or B alone. All preexisting protected objects and historical finance rows remain untouched.
- Next bounded outcome: the sole server-derived adoption/review SQL under one stream lock and exact candidate-digest validation, then make the private Us adapter use restricted v3 functions and rerun full independent signed-owner and outsider negative tests on a disposable clone.

## 2026-11-01 held increment C/D — source-derived review and sole SQL writer

**Bounded outcome:** owner-bound database source reconstruction plus one atomic derived revision adoption. A and B remain unchanged, followed by `derived_candidate_review.sql`, `derived_revision_adoption.sql`, and companion disposable SQL fixtures. The default Us adapter remains untouched.

- **C — Python canonical parity**: [RiverSong #41313231539](https://github.com/optical-lift/us/actions/runs/41313231539) **SUCCESS**, exact Noel `d2e94699605f1bd1173206a47e9e9c7f4f3f951e`. Database attested the original imported baseline digest, replayed dated events, retained unchanged January and proposed February, and matched Python's canonical `candidate_digest` byte-for-byte. Wrong owner and stale cutoff denied.
- **D — atomic SQL adoption**: [RiverSong #41313388652](https://github.com/optical-lift/us/actions/runs/41313388652) **SUCCESS**, exact Noel `6408550591526cc79da2c4705316213daa32b53e`. Database recomputed the review while holding the source stream, inserted all derived rows and sealed inside one transaction. Changed fingerprint, outsider, stale action and changed-key replay denied; same-key retry returned the same receipt, and prior financial baseline remained unchanged. Ordinary `service_role` INSERT and v1 seal EXECUTE stayed denied.
- **Independent session race**: [RiverSong #41313525020](https://github.com/optical-lift/us/actions/runs/41313525020) **SUCCESS**, exact Noel `b4f6b470cbfec47ef517505e1979d6ee9b6f3a72`. Two distinct PostgreSQL connections simultaneously attempted different approvals at the same cutoff; exactly one revision and seal survived, competing action received stale denial.
- **Us HTTP restricted adapter**: [RiverSong #41313819702](https://github.com/optical-lift/us/actions/runs/41313819702) **SUCCESS**, exact Noel `76f86d98f76801106c6291833ee61c5983fcd984`; tested Us workflow commit `6404933690b4e91815b23f6de8ca670d47e7b9ba`. New optional `us_sql_revision_writer_v3.py` operated with `current_user=service_role` through the existing Us FastAPI port with synthetic principal verifier. Visible review, adoption and replay passed; invalid bearer, outside owner and tampered visible preview denied. This is not a GoTrue test.
- **Full SQL privilege matrix**: [RiverSong #41314001334](https://github.com/optical-lift/us/actions/runs/41314001334) **SUCCESS** at exact Noel source `992754d032539773bcf832a673b88d5a84879aa1`, including the five-argument v3 function, inaccessible privileged reconstruction core, and no client grants.
- **Real GoTrue v3 gate**: [RiverSong #41314119547](https://github.com/optical-lift/us/actions/runs/41314119547) **SUCCESS** at held Us source `6cd12b39c89286bc0e19297cbef322fd32a4f9bd`, source-pinned Noel v3 `992754d032539773bcf832a673b88d5a84879aa1`. Pinned GoTrue v2.160.0 was compiled and launched natively; two independent fictional users authenticated and passed real Us FastAPI HTTP owner/outsider checks with restricted `service_role` PostgreSQL. Wrong owner, forged bearer, altered forecast, direct INSERT and old seal remained denied. No production credentials or financial data used; temporary processes cleaned. This proves genuine local GoTrue v3 acceptance, **not** parity with hosted Supabase versions.

**Protected scope:** all tests use disposable loopback PostgreSQL on dedicated RiverSong-Us-Carry, fake finance and identities, and automatic cleanup. No actual Us financial records, production Supabase migrations, Atlas or Titus release, merge, or current runtime cutover.

**Still missing after this outcome:** source-enforced owner-scoped history/read and ordinary-event application cutover without direct broad `service_role` SELECT/legacy appender, current hosted Supabase parity, dependency-complete release clone, and separate governed production migration authorization. The held A/B/C/D SQL source is **not a generated migration**, and partial success does not authorize deploying it.

## Owner choice, 2026-11-01 — universal foundation / isolated private service / post-release real practice

The owner selected **1C / 2D / 3C** after the confirmed signed v3 PostgreSQL Us HTTP success:

- Build general-purpose Carry **functions and contracts**, with a real financial Us Case as the first end-to-end acceptance. No premature Atlas dependency.
- Put a **separate restricted Us backend service** between the Us web/experience tier and the Noel-owned private database BEFORE cutting over any established Us reader/writer. This is a new *trust boundary*, not a new record source, financial plan/stream or parallel system. Noel owns the canonical SQL and grant custody; Us owns the standalone service and upstream authenticated encounter.
- Real private financial review/adoption is the goal **after** protected release. None of the passing localhost synthetic tests authorizes accessing live money now. Atlas remains separately queued.

**Next Noel dependency**: deliver a strictly owner-bound private history/stream reader and safe event/bootstrap API that a restricted standalone Us service can use without the older `UsPostgresOwnedStore` directly reading broad tables, inserting streams or calling the unrestricted v1 appender. Maintain original imported-baseline lineage and existing identities. Do not expand direct grants or rely on an upstream-supplied UUID / session GUC.

**Acceptance boundary**: no `anon`/`authenticated` grants on private tables or functions, no unrestricted `service_role` read/write through legacy functions, full stream ownership verified at the SQL source, real signed GoTrue owner/outsider denial at the isolated service endpoint, and unchanged forecast digest/replay/adoption proof. Enforce actual internal-service transport protection, and keep all tests on synthetic disposable RiverSong PostgreSQL. Release of v1/v2/v3 remains held until the complete application path is migrated, hosted runtime parity established and separate release authorization obtained.

The corresponding owner decision and next bounded Us service acceptance are preserved in `optical-lift/us`, `systems/carry/RIVERSONG_LOCAL_STAGING_STATUS.md` (commit `ba107a99557499640cbe4ad69128ea02c081b1fb`). This supplements, rather than restarts, this existing v3 completion register.

## 2026-11-01 held increment E — isolated backend owner-scoped history read

**Outcome owner / source:** Noel owns the new `backend_owned_read_v3.sql` and `backend_owned_read_postconditions.sql`, following unchanged original finance + Carry v1/v2 and held v3 A-D. Us owns a distinct service-only runtime and its signed HTTP tests. Atlas and production remain protected.

- A new dedicated `us_carry_backend` PostgreSQL role is created **NOLOGIN / NOINHERIT / NOBYPASSRLS**, with no broad financial/event table grants, no legacy appender, no ordinary write, and no adoption function. Source does not provision a lasting login or secrets; protected release must do that separately.
- The sole allowed operation in this increment is `us.carry_read_owned_history_v3(verified_owner,stream_id,after_sequence,page_size)`. SECURITY DEFINER on the private `us` schema validates exact owner/stream and returns a bounded page (max 50) of immutable event envelopes; it reveals no roster or unrelated stream and discloses no count outside the authorized history. The service must validate the actual GoTrue token before passing the verified owner; a guessed UUID alone is never an authorization source at the service boundary.
- **SQL gate:** [RiverSong #41315519663](https://github.com/optical-lift/us/actions/runs/41315519663) **SUCCESS**, exact Noel source `88e51142b8341b55c912406c47fc0ac2d9183804`. Actual `SET LOCAL ROLE us_carry_backend` proved the first and second pages, rejected wrong owner/unknown stream/oversized page, and denied raw event table SELECT, revision/line inserts, unrestricted seal and adoption. Earlier A-D tests also passed unchanged on this run.
- **Isolated service source:** Us draft adds `us_backend_history_reader_v0_1.py`, `us_isolated_service_v0_1.py`, and a disposable-only subprocess test entry. The private service separately validates the GoTrue bearer, enforces an upstream machine capability, uses the restricted database role, and returns the bounded history. No existing Us application route has been cut over.
- **Separate-process signed test:** [RiverSong #41315651754](https://github.com/optical-lift/us/actions/runs/41315651754) **SUCCESS** at Us commit `2a54c185b3d14402669e9cf525e57f42804f6a0a`. Two independent actual GoTrue users accessed a separate loopback FastAPI service process authenticated with a 32+ byte internal machine credential. The service used a true `us_carry_backend` login in disposable PostgreSQL, not an admin or `service_role`. Owner history page 1/2 and 3/4 passed, outsider/forged/missing bearer and missing/wrong machine credential denied, unknown stream and unbounded page denied, and underlying source records remained unchanged. The temporary backend role's LOGIN and PostgreSQL cluster were destroyed after the test. **This is not hosted version parity or permission to provision a production login.**

**Not done:** production-grade service deployment/network trust, confidential credential provisioning, additional source-enforced financial bootstrap and ordinary event writer through this role, full history replay/pagination consumption in Us, source dependency-complete release, and current hosted Supabase parity. All actual financial use and Atlas integration remain held.

- **Full upstream-to-service acceptance:** [RiverSong #41316256854](https://github.com/optical-lift/us/actions/runs/41316256854) **SUCCESS**, exact tested Us SHA `05d4d34f10869b05b4446fef6ac196a64eff0578` and Noel SQL source `88e51142b8341b55c912406c47fc0ac2d9183804`. An optional Us upstream typed client (with **no DB connection and no owner ID parameter**) reached an independently running loopback Carry service. That service performed fresh genuine GoTrue verification of separate fictional owner/outsider sessions, enforced its independent machine capability, and called the narrow SQL page reader through a real `us_carry_backend` database login. Correct two-page history, outsider and forged bearer denial, wrong/missing machine capability denial, no raw table access, no adoption permission, and preserved original source were observed. No default Us route or hosted deployment changed.

**Increment E acceptance:** source role privileges, bounded owner read, independent HTTP process and upstream client path all validated on local synthetic fixtures. **Do not call the broader v3 release complete.** Remaining: independent production service provisioning and private transport/credential custody, source-enforced bootstrap/ordinary event functionality via the dedicated role, full application route cutover, current hosted runtime parity, dependency-complete release clone and separate authorization. No real finance or Atlas.
