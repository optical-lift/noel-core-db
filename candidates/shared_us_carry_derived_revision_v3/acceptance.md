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

## 2026-11-01 owner decisions 1D / 2D / 3C / 4D / 5C — approval-gated Case custody

- **1D:** begin with one explicit primary financial Case, with additional Cases separate; never infer primary from last-used or plan order. Preserve each existing canonical financial plan and unique associated stream.
- **2D:** opening requires an affirmative, deliberate **Open Carry Case** request; merely reading a plan must never bootstrap Case history.
- **3C:** proposed event domain includes observations/evidence and proposed financial changes; they remain proposals until a permitted durable operation.
- **4D (new hard constraint):** another **distinct currently authorized Person** must approve before an event becomes immutable history. A self-approval, bearer supplied "approver", or same account under another session is invalid. Existing v1 event rows enforce actor=owner and v3 ordinary appender does not represent approver authority. **Do not grant it to the isolated backend before a Noel-governed Person authorization and two-actor provenance design is built and signed-tested.** Existing old tests do not prove this new requirement. Financial revision adoption also requires authority resolution and is held.
- **5C:** automatic repair only for fully source-attested, deterministic reconstruction of missing historical records; never fabricate missing witness, overwrite records, infer a revision, or treat an inconsistency as permission to restart. If proof is incomplete, fail closed with a review/blocked status.

**Next single bounded outcome (F):** source-enforced deliberate **pending Case opening request**, not a CASE_OPENED event. Source proves exact owner and canonical adopted revision, rejects preexisting streams, deduplicates requests, supports at most one explicit primary selection, and grants only staged-request EXECUTE to isolated `us_carry_backend`. Approval authority and actual Case/event append are explicitly outside F. An outsider, missing baseline, duplicate key change, additional-before-primary, self-approval attempt, or raw stream/event INSERT must not produce new history. Run independent two-user GoTrue service and disposable SQL tests. No broader workflow completion claim until distinct-Person source authority is actually implemented.

## 2026-11-01 F source receipt — deliberately pending primary open request

- **Source:** `approval_gated_open_request_v3.sql` and `approval_gated_open_request_postconditions.sql` on held Noel source `e520c9b54cc8115573b4e529be0ed5c6e05a0b46`. This adds `us.carry_financial_open_requests_v3` with immutable append-only request records, owner+plan FK, explicit `primary` choice, exactly one request per financial plan, exactly one primary request per owner, source-attested originally adopted revision/line digest, stable action-key retries, and `pending_independent_approval` only. No Case stream, financial revision or Carry event is inserted. It does not invent a second Person or grant approval/append/adoption.
- **Disposable SQL proof:** [RiverSong #41317847493](https://github.com/optical-lift/us/actions/runs/41317847493) **SUCCESS**. Owner request, same-key replay, wrong owner, existing stream, unadopted source, multiple primary/early additional, conflicting key, raw stream INSERT and unapproved appender denial tested under `SET LOCAL ROLE us_carry_backend`. Synthetic legacy adopted baseline staging used temporary isolated-admin trigger disable/re-enable solely in a ROLLBACK test fixture; no persistent trigger relaxation or migration.
- **Us service scope:** `us_backend_open_request_v0_1.py` restricted SQL adapter, optional primary-open POST on the separate internal GoTrue-verified Carry service, and optional upstream Us client. Only explicit POST stages an opening. Not wired as a default application path.
- **Signed end-to-end gate:** [RiverSong #41318217489](https://github.com/optical-lift/us/actions/runs/41318217489) dispatched and must independently report success before claiming the new HTTP acceptance.

**Source decision unresolved, kept as a mandatory gate:** v1 immutable event rows require `actor_auth_user_id=owner_auth_user_id`; no currently source-authorized distinct-approver reference is attached to a staged Case request or canonical event. Existing Noel universal connected-Person/permission authority must be traced and tested before a new approver may sign off. No simple "approved=true", JWT metadata, same-user second session, service-held approval secret or client-supplied approver field will satisfy owner choice 4D. At the actual approval gate, re-attest original source and the approver's current authorization under the same database transaction, preserve identity, and prove concurrent disjoint approvals yield one event.

**5C historical custody:** F intentionally refuses existing streams and does not repair them. Subsequent deterministic source-proven repair must verify the entire existing immutable chain and exact original revision digest first; any missing/contradictory proof yields blocked review, never synthetic events.

Next unfinished outcome is **independent, source-checked approver identity and authority with an immutable proposal/decision association**, not blanket granting `us_carry_backend` access to the legacy appender. All held migrations, default Us runtime, production, real money and Atlas remain untouched.

### 2026-11-01 F final signed service acceptance — PASS, scope deliberately limited

- [RiverSong #41319794837](https://github.com/optical-lift/us/actions/runs/41319794837) **SUCCESS** at exact Us SHA `6137a05bfab76e4d20b197b7f34ba1d175fa082b`, pinned Noel SQL `e520c9b54cc8115573b4e529be0ed5c6e05a0b46`. This supersedes the preceding pending and unsuccessful attempts, while preserving them as test history.
- Genuine GoTrue v2.160.0 signed both independent fictional users. The upstream Us client called a **separate localhost Carry service process**, which revalidated the token and required the internal machine credential before invoking `carry_request_financial_open_v3` under an actual disposable `us_carry_backend` login. Owner accepted the explicit primary request; same action returned replay, changed key was rejected, outsider and second primary were denied. Case stream count for the selected primary plan remained zero, no new canonical Carry event was written, and the original seeded Case history remained unchanged. Backend role had no raw SELECT/INSERT or seal/adopt authority. The temporary Postgres/Auth/service resources were cleaned up.
- The previous signed attempts [#41318217489](https://github.com/optical-lift/us/actions/runs/41318217489), [#41318765680](https://github.com/optical-lift/us/actions/runs/41318765680), and [#41319287207](https://github.com/optical-lift/us/actions/runs/41319287207) failed test scaffolding, respectively due to a broken service module during source editing, an adapter exception-remapping bug, and an overly broad test-owner event-count assertion. All three were corrected and the final test passed.
- This closes **F request-staging only**, not the larger independent approval requirement. An authorized distinct Person source predicate, two-actor immutable approval attestation, and atomic canonical CASE_OPENED + attested BASELINE_IMPORTED remain unimplemented. Never treat this `pending_independent_approval` receipt as approval. No existing production data, hosted migration, default Us route, or Atlas release was changed.

## 2026-11-01 G1 — native canonical Person reviewer nomination (not approval)

**One bounded outcome and source owner:** Noel retains primary financial Case and source permissions in its private `us` schema. A pending Case-open request may receive **one owner-directed nominated reviewer** referenced by already existing native Reality Person and active Auth binding. No duplicate Person, Ledger, membership, finance source or event/custody system is created. The Us isolated service owns only the optional authenticated HTTP adapter.

**Verified native-source authority finding:**
- `supabase/migrations/20260925014915_atlas_reality_ledger_core_v1.sql` creates `reality.entities` and `reality.auth_person_bindings`; `supabase/migrations/20260925134609_atlas_reality_authenticated_access_cutover_v1.sql` resolves the current canonical Person through an active Auth binding.
- `supabase/migrations/20261024231137_shared_foundry_native_person_ledger_reviewer_v1.sql` expressly distinguishes a native Ledger connection from content-read permission. Ledger relationship or organization/worker role MUST NOT imply authority to read private Us finances or approve a Carry event.
- A Case-specific consent/approval grant does not yet exist in the released Carry source. The isolated service cannot elevate `service_role` or re-enable the old appender to bypass this requirement.

**G1 held source:** `primary_reviewer_nomination_v3.sql` adds append-only `us.carry_primary_reviewer_nominations_v3` and an exact owner-scoped `us.carry_nominate_primary_reviewer_v3` callable only through `us_carry_backend`. It verifies the original pending primary open request, refuses an already opened stream, requires an actual distinct current canonical Reality Person with unambiguous active Auth binding and unbanned/nonanonymous account, and uses stable idempotency with source row locks. Nomination returns `pending_nominee_acceptance`, explicitly **no financial disclosure, no approval, no Case/event creation**. No target consent or permission is fabricated.

**SQL acceptance:** [RiverSong #41327980025](https://github.com/optical-lift/us/actions/runs/41327980025) **SUCCESS**, pinned Noel source `9c81e356a54f63372ca687264b15600891a7c1b9`. The runner applied original finance and Carry F SQL plus a deliberately minimal synthetic mirror of the native Reality identity shape **inside disposable PostgreSQL only**. Negative tests rejected outsider owner, self, disputed/retired Person, conflicting nomination, direct table SELECT/INSERT and legacy event appender; same-key retry returned the original nomination; selected financial Case remained unopened and event count remained zero.

**Signed HTTP acceptance:** [RiverSong #41328278569](https://github.com/optical-lift/us/actions/runs/41328278569) dispatched with two real signed fictional GoTrue users mapped to separate canonical Person fixture records. Its result is independent from the SQL pass and must be checked before claiming complete G1 service acceptance.

**Still unfinished:** G2 nominee authentic acceptance and owner-scoped financial disclosure permission (with independently withdrawable/expiring scope), G3 live source-authorized approval with immutable proposer/approver identities, atomic CASE_OPENED + attested BASELINE_IMPORTED exactly once, downstream ordinary event and derived adoption second-Person approval, source-exact historical repairs, full protected clone/hosted parity and explicit release. Default Us, production hosted Supabase, real finance, Atlas and mainline stay untouched.

### Gate G1 final signed two-user acceptance — PASS, no approval granted

[RiverSong #41329171691](https://github.com/optical-lift/us/actions/runs/41329171691) **SUCCESS** on exact Us SHA `f70c5710b0c97416980502621ece74f0fe7c150f`, pinned Noel source `1ccab78490868029234143d790119bfaad8896b5`. Official GoTrue v2.160.0 signed two distinct synthetic user accounts. Each was bound to a distinct canonical Person in a disposable native-Reality-shaped fixture; the owner authenticated through the optional upstream Us client and independent private Carry service, which reverified the bearer and called `us.carry_nominate_primary_reviewer_v3` through an actual narrow `us_carry_backend` login.

Positive evidence: exact pending primary request, nominated Person remains `pending_nominee_acceptance`, idempotent replay returns the same nomination. Negative evidence: outsider, owner-self nomination, conflicting nomination, raw backend table writes/reads, missing/forged bearer and machine capability. No financial disclosure, approval authority, Case opening, Carry event or adopted financial revision resulted. The isolated direct SQL diagnostic was rolled back. Test-only temporary PostgreSQL/GoTrue/service resources were destroyed.

Earlier signed attempts [#41328278569](https://github.com/optical-lift/us/actions/runs/41328278569) and [#41328756372](https://github.com/optical-lift/us/actions/runs/41328756372) failed at the new HTTP adapter (a strict JSON UUID decoding mismatch), not SQL source authorization. Explicit UUID field decoding plus a targeted request-model preflight resolved it, with final complete signed proof green.

**G1 closes ONLY nomination.** Next Gate G2 must create **active, exact-Cary-Case-scoped reviewer authority** via independently authenticated nominee acceptance and deliberate owner-issued financial disclosure/approval scope, with revocation/expiration and source revalidation. Nomination/connection alone grants nothing. Gate G3 must attest distinct proposer/approver identities immutably and perform a single atomic source-attested opening; no legacy appender/adopter grant beforehand. Hosted parity, protected clone, actual financial use, default Us cutover and Atlas remain held.

## 2026-11-01 Gate G2 — distinct signed nominee consent, explicit owner time-limited attestation grant and revocation

**Owner choices:** 1D / 2D / 3C / 4D / 5C remain governing. No automatic Case creation, no approval by owner or service, no automatic repair without original-source proof.

**One bounded outcome:** source-backed consent and strictly narrower review of the pending primary Case *opening-attestation*, rather than permission to approve the Case or read financial lines. Noel SQL file `primary_reviewer_acceptance_scope_v3.sql` owns all source predicates. Independent Us HTTP routes, typed backend and upstream adapters own transport only; no alternate Case, Person, permission, Ledger or finance store.

**Dependencies:** existing F pending primary-open request and G1 canonical distinct-Person nomination, original `reality.entities` and `reality.auth_person_bindings` plus current genuine GoTrue Auth user, and dedicated `us_carry_backend` login. No Atlas migrations or existing Word/Work permission decisions changed.

**What was built in source:** (1) append-only nominee acceptance unique to the nominated canonical Person; (2) a separate owner action grants only `opening_attestation_only` access for an explicitly chosen expiration between five minutes and seven days, after acceptance; (3) owner may append an irreversible revocation, including after nominee identity retirement; (4) the nominated signed Person may read **only** a bounded original baseline-attestation summary after both actions, while the grant is live. The source rechecks owner/nominee canonical Auth bindings, exact pending request, non-opened Case, unrevoked/valid expiry and original adopted revision plus exact line-count/digest before every read. No plan name, line amount, account, owner ID, raw event or approval route is exposed. All consent/grant/revocation rows immutable and all private tables have no raw backend role SELECT/INSERT. No approval or event/appender/adoption grant.

**SQL evidence:** [RiverSong #41330466824](https://github.com/optical-lift/us/actions/runs/41330466824) **SUCCESS** using pinned source `c8b1c2b3ca152e7a5eba3208c990ad7b84539db7` and disposable native Reality identity mirror. Negative tests: nomination alone and acceptance alone cannot read; wrong actor cannot accept/grant/revoke/read; past and over-seven-day expiry denied; same key idempotent, conflicting keys fail; only amount-free signed reviewer packet returned; revocation immediately prevents new reads and cannot be replayed into an active grant; zero canonical Case events.
**Independent signed service acceptance:** [RiverSong #41331133639](https://github.com/optical-lift/us/actions/runs/41331133639) **SUCCESS**, exact tested Us SHA `26fa13e10b0c1c7d912f4c1290ad52980dfb5214` with pinned Noel SQL `c8b1c2b3ca152e7a5eba3208c990ad7b84539db7`. Distinct genuine GoTrue bearer for nominee acceptance; owner separately granted amount-free `opening_attestation_only` access for a bounded future expiry; wrong actor/forged token, consent-without-grant and owner impersonation denied; owner revocation removed access; neither role may approve an event or open the Case. Synthetic fixtures and private service cleaned. Earlier [#41330720416](https://github.com/optical-lift/us/actions/runs/41330720416) failed **test harness only** due to a missing `datetime` import, corrected before the successful rerun.

**Protected scope:** hosted Supabase, separate protected release, production credentials, true current hosted Auth version parity, default Us route, real financial data and Atlas untouched. Gate G3 remains: immutable two-Person proposal/decision provenance, source authorization to approve actual opening and import of attested baseline atomically, and later ordinary events/adoption/repair under the same permission law.

## 2026-11-01 Gate G3 — separately authorized signed two-Person primary Case opening

**Narrow outcome:** source-owned owner authorization to approve opening is separate from G2 read scope. A currently bound **different** canonical Person signs the precise two-event opening decision; Noel uses the unchanged original Carry v1 stream/event writer, not direct financial table edits or a new appender. Owner/approver canonical Person and auth IDs, exact source revision/digest/line count, grant identity and both canonical event IDs are bound in immutable `carry_primary_open_approval_decisions_v3` within the same transaction as stream creation and the `CASE_OPENED` / `BASELINE_IMPORTED` pair. All rows remain private, no backend direct INSERT/SELECT or original v1 event-writer EXECUTE. Grant and decision API only via restricted backend source functions; the independent service must verify real GoTrue separately.

**Source files:** `primary_approved_open_v3.sql` and `primary_approved_open_postconditions_v3.sql` on original held draft PR. Explicit owner expiry cannot outlast currently unrevoked G2 permission. Nominee accept/read alone never authorizes approval; wrong caller, owner self-approval, stale original digest, preexisting Case, conflict and two competing sessions must fail or resolve to same event IDs.

**SQL evidence:** [RiverSong #41331910431](https://github.com/optical-lift/us/actions/runs/41331910431) **SUCCESS**, Noel pinned SHA `af34c6cee483d4f26cafec7f1e0f59200d2c21a4`. Negative privilege and scope tests as above, atomic exactly two original v1 event sequences and digest continuity; no financial revision altered. [RiverSong independent two-signed-GoTrue-user G3 concurrency #41332199201](https://github.com/optical-lift/us/actions/runs/41332199201) **SUCCESS**. Exact tested Us SHA `37af31b455b7a10a665277b7c76d99fe9a4108da` and pinned Noel SQL `af34c6cee483d4f26cafec7f1e0f59200d2c21a4`. The genuine signed owner gave separate opening authority after G2, a distinct real GoTrue Person signed the approval and two independent concurrent HTTP calls (separate PostgreSQL connections) yielded one fresh two-event canonical Case and a replay of the identical stream/decision; changed decision denied. `CASE_OPENED` / `BASELINE_IMPORTED` event IDs, v1 digest continuity and unmodified original revision were verified. Prior G2 read-only scope never authorized approval; owner self-approval and absent grant denied. All test data, roles/services were disposable. **G3 primary Case opening is now source/HTTP/concurrency verified in held draft only; it is not deployed or authorized for real finances.**

**Unfinished:** 4D each ordinary event and derived adoption decision, 5C source-proven repair, additional nonprimary Cases, complete protected hosted clone/runtime/credential provisioning, default Us route cutover, production, Atlas and real financial use. Both PRs remain draft.

## 2026-11-01 — new personal-use release choices and NO-GO record

The owner selected **1D/2D/3D/4D/5D/6D/7D/8C/9D/10D**, in addition to already governing **1D/2D/3C/4D/5C**. The [ordered Us personal-use release plan](https://github.com/optical-lift/us/blob/feature/carry-event-custody-contract-v0-1/systems/carry/PERSONAL_USE_RELEASE_COMPLETION_PLAN_2026-11-01.md) governs future bounded work; this Noel register remains canonical source acceptance rather than creating new status authority.

**Current verdict NO-GO for actual personal financial data:** G3's distinct-Person atomic Case-opening proof is only synthetic/held. A different currently source-authorized Person must approve **each ordinary event** (and any eventual financial revision adoption). The existing `carry_append_ordinary_event_v3`, `carry_adopt_derived_revision_v3`, legacy Us `/carry/approve` and old baseline bootstrap do not satisfy the stronger 4D rule. No broad financial access is implied by G2's attestation grant or an Atlas Person/Ledger relationship. Owner additionally requires selected-Case full disclosure with explicitly limited expiry/revocation (6D), multiple eligible approvers but one specific independent decision per event (5D), per-item original source signoff and 2025–26 source-proven historical inclusion, and **10D draft hold until full Atlas integration accepted**.

**Noel next owned portion:** P0 audit all current and legacy write/privilege paths with negative source-signed no-bypass test; P1 multi-Person per-event approval and immutable witness chain; P2 source-governed case-level disclosure; P3 source-proven baseline and line-item review; protected migration/security parity much later. Existing Noel PR #2436 stays draft, no production/new authority/real finance touched. Atlas's existing register and full permission/browser acceptance remain separately owned.

## 2026-11-01 P0 — no-bypass source floor for personal-use release (held)

Owner decisions **1D/2D/3C/4D/5C** + **1D/2D/3D/4D/5D/6D/7D/8C/9D/10D** continue to control. This is one bounded **Noel source privilege floor** with an Us HTTP negative counterpart, not P1 event governance or a production migration.

**Source files:** `personal_use_p0_no_bypass_floor_v3.sql` and `personal_use_p0_no_bypass_postconditions_v3.sql`. Revoke external EXECUTE on v1 raw append, owner-only v3 ordinary append and owner-only derived financial adoption from all application roles (including `service_role` and `us_carry_backend`). Explicitly revoke legacy v1 direct `service_role` Case-stream INSERT and broad Case stream/event SELECT, without touching current narrow history access and G3 independent two-Person approved opening. These rules apply **after the historical v3 fixture regressions**, not before. Earlier direct-stream creation grant was a material additional P0 discovery.

**Actual RiverSong receipt:** [#41334500989](https://github.com/optical-lift/us/actions/runs/41334500989) **SUCCESS**, tested Us `5c54e93eb8d6d606386e62a6352cd46c3e28aea2`, pinned Noel SQL `17263b9e1143db88594706ffaffe3fc05953fb25`. SQL role catalog and negative EXECUTE denied; G3/source reader preserved. Us synthetic HTTP [#41334467492](https://github.com/optical-lift/us/actions/runs/41334467492) **SUCCESS**; old bootstrap/ordinary approval/adoption routes now return 410. The older [#41334226935](https://github.com/optical-lift/us/actions/runs/41334226935) failure was an unupdated historical positive HTTP adoption assertion, fixed to require denial 410.

**Independent signed GoTrue acceptance:** [#41334678187](https://github.com/optical-lift/us/actions/runs/41334678187) dispatched, result not yet claimed. Refer to [Us P0 route-authority matrix](https://github.com/optical-lift/us/blob/feature/carry-event-custody-contract-v0-1/systems/carry/PERSONAL_USE_P0_ROUTE_AUTHORITY_MATRIX_2026-11-01.md).

**Still held:** existing Python direct-owner adapters remain prototype source, neither approved nor default-runtime-released. P1 must introduce one exact source-authorized independent canonical Person decision for **each** ordinary event, P2 specific full-Case reviewer disclosure, P3 provable source backfill and per-item owner confirmation, Atlas P6 integration and separate protected release. No current hosted database privilege, actual finance or real owner use was altered. Retain one existing completion register, no Atlas fork.
