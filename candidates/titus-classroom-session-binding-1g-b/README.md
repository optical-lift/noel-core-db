# Titus Build 1G-B — live-shape session/Person source denials, isolated PG17

**Owner:** Noel source-owned Titus classroom gates. **Base:** [1F source issuer draft #2471](https://github.com/optical-lift/noel-core-db/pull/2471).  
**Date:** November 4, 2026. **Status:** source/test draft, neither migrated nor released.

## One bounded outcome

Replace the old, direct `titus.test_person` / `titus.test_user` shortcut **within one new test cluster only** with the actual **live-source-shaped** function bodies of:

- `atlas.existing_person_claim_signed_actor_v1()` — current nonanonymous confirmed GoTrue `auth.users` and matching `auth.sessions`, not a client-supplied actor.
- `titus.current_authenticated_person_entity_id_v1()` — current session + active canonical `reality.auth_person_bindings`.
- `atlas.current_person_id_v1()` and `atlas.current_principal_id_v1()` — current signed Person to active root principal.

The `auth.uid()` and `auth.jwt()` fixture helpers **read synthetic unverified request-claims GUCs**. In real production, GoTrue and PostgREST verify JWT signatures before setting request claims. This new fixture does not run GoTrue, does not check any cryptographic signature and **must never count as genuinely authenticated two-human consent**. It tests the authorization logic *after* claimed identity arrives.

## Dependencies and protected scope

Depends on the existing held fixture-only original event, source participation, read/append and offering issuer candidates (Noel PRs #2469–#2471). Uses only invented UUIDs, an active fake Atlas Teaching Offering and one fake enrollment in a fresh private-socket local PostgreSQL 17 directory on RiverSong, unique port `55443` (never protected Atlas clone `55432`). All extra source-shaped auth tables/functions are test-only, and this branch adds no production migration.

Never copy this test-only `auth.jwt()` or `auth.uid()` into the shared Supabase project. No real users, approval, student data, source disclosure grants, writer gate, teacher appointment, Atlas schema or production are changed.

## Acceptance matrix

- Reject absent session, wrong person's session, expired session; recheck on each source action.
- Reject an outsider accepting a seat; only the current principal for the exact Atlas Ledger offers.
- Allow accepted fake teacher but **not** read before learner's named consent; reject wrong named teacher and false acceptance.
- Allow exact synthetic learner consent in the fixture; reject anonymous, unconfirmed, banned, retired Person binding, revoked Auth session and removed issuer Ledger authority.
- After learner withdrawal, teacher cannot read; immutable event custody is preserved; independent original writer gate remains **false**.
- Anonymous role cannot call source APIs or read private session/participation tables.
- Runner must pass strict disposable PG17 data-directory, no TCP and no source credential checks, plus source exact-SHA carrier verification.

## Completion register

| Gate | Status / evidence |
| --- | --- |
| Earlier 1F fictional offer/accept/withdrawal & event history | **PASS**, [RiverSong #41884149777](https://github.com/optical-lift/titus/actions/runs/41884149777) |
| Titus 1G-A signed-user HTTP transport mocks and no-release build | **PASS**, [RiverSong #41888181853](https://github.com/optical-lift/titus/actions/runs/41888181853) |
| Live-source-shaped Postgres session/Person binding proof | **PASS — [RiverSong #41892880522](https://github.com/optical-lift/titus/actions/runs/41892880522), pinned source SHA `a725a540a2186e9d4b436893831b23ed4f61e9e2`** |
| Actual GoTrue-signed JWT, PostgREST signature verification, two distinct real consenting people | **NOT DONE** |
| Source rights review / Teaching edition authorization | **NOT DONE** |
| True source issuer/writer migration, authenticated grants and production release | **NOT DONE** |
| Titus UI enabled or public deployment | **NOT DONE** |

**Next:** exercise two *genuinely* signed and separately consenting accounts and an authorized principal against the governed source in an isolated production-shaped environment, including actual PostgREST JWT checks. Do not call a GUC-based fixture or a fabricated test consent such a proof. The event writer gate requires its own separately approved source release.

## Exact verification receipt

**PASS — 2026-11-04**. [Titus RiverSong carrier #41892880522](https://github.com/optical-lift/titus/actions/runs/41892880522), workflow SHA `e6e8b94c6f1b40baa94faa84cf1da6afdbab1be6`, fetched exact Noel source/test SHA `a725a540a2186e9d4b436893831b23ed4f61e9e2` and passed all four independent disposable PostgreSQL 17 test clusters on private-socket ports 55437, 55439, 55441 and **55443**. The protected Atlas clone port 55432 was untouched. The fourth cluster logs confirm the source-shaped session table/Person-binding denial matrix, the principal/teacher/learner source events, withdrawal and the writer still false. The runner cleaned up its isolated source checkout.

**Closed:** source-shaped current-session/Person-binding **synthetic test** behavior. The claims originate from a test-only GUC, so the test does **not** verify a GoTrue cryptographic signature, real authenticated sessions or independent human assent. **Not closed:** two genuinely authenticated people, actual principal jurisdiction, rights-cleared edition, production source issuer/writer release, or a live Titus classroom. Keep Noel PR #2472, PR #2471 and Titus PR #41 as drafts; do not merge or deploy on this result.

**Next bounded necessity:** cryptographically verified GoTrue/PostgREST signed sessions and distinct participant acceptance against an approved, isolated source-backed environment, with separate source release authority and explicit rights approval. Do not substitute synthetic `request.jwt.claims` for this gate.
