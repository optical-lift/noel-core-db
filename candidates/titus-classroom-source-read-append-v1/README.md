# Titus source read/append — Build 1E, RiverSong proof

**Date:** November 4, 2026. **Source owner:** Noel. **Status:** unreleased, stacked source candidate.

## Bounded outcome

Complete the three-RPC contract used by [Titus PR #38](https://github.com/optical-lift/titus/pull/38), without treating a successful OAuth login, an Atlas enrollment, historical Formation Teacher, or a fictional role switch as permission. [Noel PR #2469](https://github.com/optical-lift/noel-core-db/pull/2469) establishes a **hard-closed** classroom participation issuer and a source-authorized `authorize` candidate. This increment adds source-only `read` and atomic `append` counterparts.

## Source and mechanism

- `candidate.sql` adds a private `titus.classroom_pilot_read_current_v1` projection and a locked, idempotent `titus.classroom_pilot_append_current_v1`. Both call `titus.classroom_pilot_authorize_current_v1` afresh. The append operation checks the signed Person after acquiring the row lock and before it can create an original event.
- Thin `public.titus_classroom_read_self_api_v1(p_thread_id)` and `public.titus_classroom_append_self_api_v1(p_thread_id,p_command)` are proposed, **not deployed**, for authenticated source transport. Neither accepts actor, Person, role, source receipt, edition, or roster metadata from a caller.
- Each event is stored exactly once in the original append-only `titus.classroom_events_v1` carrier. Homework status is a projection over the same event stream. The event root's hard-false gate and immutable triggers remain intact.
- The source validates exact operation ID and version, shape/body/part, replay payload and actor, latest homework original, reviewer role, revision parent and original preservation. A same-operation retry returns the same event; stale competing writes cannot silently overwrite earlier messages.
- The source is **sample-fixture only**. All actual Titus Formation response originals, approved teaching editions, Atlas institutional communications and learner consent remain protected and untouched.

## No-release boundaries

The previous `titus.classroom_pilot_assignment_issued_v1()` issuer remains **hard false**. The independent `titus.classroom_authority_gate_v1()` writer gate also remains **hard false**. Even an otherwise well-formed authorization receipt cannot create a live classroom write until both *authentic* source issuance and authorized writer custody exist. The candidate does not replace either false gate, create real membership, add an OAuth user, grant direct table access, or migrate any source.

The proposed public transports would be callable by authenticated users only **after a deliberate, separate release**. Each request re-resolves signed current canonical Person and active exact classroom authorization. A service-role key, test HMAC or user-chosen teacher role is not needed or permitted in the Titus app.

## Disposable test receipts

A fresh RiverSong PostgreSQL17 cluster is used, with `listen_addresses=''`, a unique private Unix socket and port `55439`. It does **not** access the protected Atlas/Noel `55432` clone, persistent source DB or any paid Supabase branch.

Fixtures use an exact, frozen source copy of the original event schema from [Titus Build 1 PR #35](https://github.com/optical-lift/titus/pull/35), plus source-identified fictional Persons and explicitly unsafe-for-production GUC identity stubs. Both hard-false gates are tested *before* fixture-only overrides. Positive tests exercise two distinct fictional people, original submission, idempotent same-payload retry, changed retry rejection, stale version, wrong parent, teacher review, learner revision, completed review, continued open discussion, cross-Person read, outsider/approved-edition denial, revoke, physical immutability and closure of both gates. The scratch cluster is destroyed after the run.

**Important limitation:** A PG17 fixture using simulated identities is **not** a positive test of genuine GoTrue current-session source issuance or an authorization grant for actual learners. Native `read` and `append` are source-custody candidates until that evidence exists.

## Completion register

| Gate | Status |
| --- | --- |
| Exact UI/server contract and signed-user bearer transport | [Titus PR #38](https://github.com/optical-lift/titus/pull/38) — RiverSong PASS |
| Signed Person and assignment source contract | [Noel PR #2469](https://github.com/optical-lift/noel-core-db/pull/2469) — source-only, hard-false issuer; native test pending |
| One source-read projection from exact event carrier | Implemented, native test pending |
| Atomic append, original preservation, exact retry and role-specific feedback | Implemented, native test pending |
| Real signed Person/assignment issuer | **Absent — hard false** |
| Actual source schema release / direct production access | **Not done** |
| Real two-person deployed UI on permanent shared records | **Not done** |
| RiverSong native PG17 source acceptance | **Pending** |

**Next unfinished increment after native proof:** establish genuinely governed learner invitation/acceptance and teacher appointment issuance, then source-authorize these exact RPCs for a private signed two-Person pilot. Only then connect the approved classroom UI's browser-local projection to the real server endpoint behind a feature gate.
