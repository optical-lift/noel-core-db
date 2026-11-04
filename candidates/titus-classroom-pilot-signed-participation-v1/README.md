# Noel source candidate — signed classroom participation for Titus sample-content pilot

**Date:** 2026-11-04. **Owner:** Noel source. **Status:** draft, not applied.

## One bounded outcome

Before implementing any real two-person Titus classroom, prove that a signed current canonical Person, not a selected teacher/learner UI role, can be matched to **one explicitly assigned classroom and one permitted operation**. This builds on the append-only event root in [Titus PR #35](https://github.com/optical-lift/titus/pull/35) and the Next server route [Titus PR #37](https://github.com/optical-lift/titus/pull/37), validated by RiverSong. It does not touch historical Titus Formation evidence or teacher binding.

## Recovered source facts (read-only, November 4)

- Existing `titus.current_authenticated_person_entity_id_v1()` resolves a canonical Person from an actual current signed Supabase Auth user and active Auth session, using `reality.auth_person_bindings`.
- Existing `atlas.existing_person_claim_signed_actor_v1()` additionally requires a confirmed, nonanonymous, active user/session.
- Atlas already has `teaching_course_offerings`, `teaching_enrollments`, root authority and offering roster readers. **An enrollment is not a teacher appointment**; a course creator or Ledger root is not automatically the teacher reviewing learner work.
- The user asked for functional software on RiverSong using sample teaching content, **not** paid Supabase dev branches or real Formation releases.

## Source candidate

`candidate.sql` creates private `titus.classroom_pilot_participation_v1` and `titus.classroom_pilot_parts_v1` tables. Per thread it holds, at most, one explicitly appointed learner and one explicitly appointed teacher, with exact canonical Person, state, effective/expiry/withdrawal, issuing Person and receipt ID. Both private tables have RLS and no direct `anon`/`authenticated` access.

The private `titus.classroom_pilot_authorize_current_v1(p_thread_id,p_operation)` calls BOTH existing current-signed actor checks. It verifies canonical Person, `source_kind='fixture'`, exact active membership, operation-specific role, live bounds and source-owned allowed parts. A narrow `public.titus_classroom_authorize_self_api_v1` makes ONLY that authorized projection available to authenticated callers. The browser cannot supply a Person, role, roster, teaching edition or source receipt.

**Important: the core issuance gate `titus.classroom_pilot_assignment_issued_v1(...)` is hard false.** No membership row, however well-formed, creates authority until a legitimately governed teacher assignment and learner acceptance/participation issuer exists. The source must establish its own evidence and revocation lifecycle before this gate can ever be replaced. The source's public `read` and `append` operations are **not** implemented in this increment; they must re-check Person and exact role at the time of the operation and reuse the immutable event root with an atomic version lock.

## RiverSong proof

`fixture.sql` uses **explicitly unsafe-for-production** fake signed identity functions and synthetic Persons/threads. `postconditions.sql` checks: hard-denied even with active-looking membership; exact student read/submit without feedback authority; exact teacher read/review without student submission authority; unrelated Person, wrong class, non-fixture material and invented operation denials; revoked and expired permission denial; malformed parts denial; RLS and no roster exposure; restoring the issuer hard false after a test-only positive override.

`scripts/test-titus-classroom-pilot-riversong-pg17.sh` creates a **new disposable** PostgreSQL17 cluster on RiverSong, short private Unix socket port `55437`, refuses Atlas protected clone port `55432`, verifies exact cluster data directory/version/no TCP, runs the fixture in isolation, destroys the temporary cluster on all exit paths. The GitHub workflow runs only on the candidate branch and uses the existing `[self-hosted,macOS,X64,lex-research]` RiverSong runner.

## Acceptance register

| Gate | State |
| --- | --- |
| Source definition / No live changes | Implemented in draft |
| Signed Person resolver reuse | Named actual live source functions; **runtime uses test stubs only** |
| Exact classroom member/role/part and default-false issuer | Implemented; RiverSong test pending |
| Negative cases, expiry/revocation and RLS | Test written; RiverSong pending |
| Real source-issued teacher and learner participation | **Absent — hard false** |
| Three source-backed authorize/read/append RPCs | Authorize candidate only; read/append outstanding |
| Two actual test accounts against live authorization | Not attempted |
| Production, Preview, migrations, source grants | Unchanged |

**Next owner-level development:** build a real principal-signed assignment + learner acceptance/withdrawal issuer using the existing Atlas Teaching custody, and prove real signed sessions, without rewriting Formation history. Then implement and retest reader and atomic writer with operation-specific source checks. Nothing in this PR authorizes releasing it today.
