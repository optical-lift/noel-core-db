# Titus Formation response Work — B2A source-only carrier

**Prepared:** November 3, 2026  
**Status:** A source proposal and disposable structural tests, **not an approved migration, deployed RPC, granted Person authority, released curriculum or working student exchange**.  
**Owner / tracker:** [Noel issue #2461](https://github.com/optical-lift/noel-core-db/issues/2461).  
**Titus consumer:** [Build B1 draft #27](https://github.com/optical-lift/titus/pull/27) and its [completion register](https://github.com/optical-lift/titus/blob/work/titus-teaching-work-build-b1-20261103/docs/TITUS_TEACHING_WORK_BUILD_B1_REGISTER_20261103.md).

## Why this is a separate bounded increment

Live read-only schema inspection verified existing original `titus.formation_responses` and `titus.teacher_person_bindings`, but no source-issued Person-specific, reviewer-to-learner disclosure mandate or released teacher-feedback writer. The current `public.titus_submit_formation_response_self_api_v1` authorizes one learner's *own* response; it does not authorize another Person to read that answer or change its status.

The smallest new durable fact not represented by the current Formation response record is **a teacher's feedback on one exact learner submission and the subsequent learner revision's relationship to it**. Do not overwrite the learner's raw answer and do not create another student-work source table storing that text.

## B2A proposed carrier

`candidate.sql` creates one **private, append-only event** relation: `titus.formation_response_work_events_v1`. Each event refers to an existing `formation_response_id`; no response body is copied into the event record.

- **First event:** feedback on an existing learner original response.
- **Second:** a separately submitted learner response tied to the exact preceding `needs_revision` feedback. The revised text remains in another `titus.formation_responses` original row, not this event table.
- **Third:** feedback on precisely that latest revision; `reviewed` is acknowledgement, not mastery/grade/approval.
- No further modification is permitted once a feedback event is `reviewed`. A review may request another revision only after a current revision and new response, subject to source limits in a future writer.

The table carries exact source root, Formation response/Unit lineage, program, separately asserted curriculum edition and teaching-release receipt references, the learner Person ID, the event's actor Person ID, ordered event IDs, body for feedback only, and timestamp. **In this staged carrier, curriculum_version_id and teaching_release_ref are UUID-shaped provenance slots, not proof of an actually reviewed or released edition**: no authoritative release mapping/read exists yet, and the SQL does not manufacture it. They MUST be validated against future source-governed release/rights proof before any real writer is enabled.

The trigger serializes each Work thread by locking the existing root response, validates a real Formation unit/program/profile relation, requires an active learner Person binding to that historical profile at insertion, and enforces contiguous predecessor/order and response/question lineage. **A teacher's ability to read or review another Person's work is NOT established by these checks.** All events are append-only; source original answer text remains in `formation_responses`.

The source `titus.formation_response_work_authority_gate_v1()` deliberately returns **false**. The proposed table grants no direct access to `anon` or `authenticated`, has RLS enabled, exposes no public RPC and does not create any role, Mandate, Organization, Atlas Course or Enrollment. Even if the candidate were mistakenly applied, inserts would remain rejected until a separate source-owned gate is replaced. Replacing this gate without real reviewed authority is **not authorized**.

## Test scope and limitations

`fixture.sql` creates a **miniature fictional Postgres 16** subset of the existing Formation schema; it does NOT restore a production snapshot or test actual Auth/GoTrue, RLS with genuine user sessions or source-rights metadata.

`postconditions.sql` first proves that the candidate is closed by default. **In the disposable test database only**, it replaces the gate with a true fixture function to test the foreign keys, structural validation and immutable history transitions. It restores the false gate at the end. Positive structural insert tests are not proof that any reviewer was authorized; the fixture intentionally has no real reviewer mandate. This isolated override must never be copied into a release.

The source workflow uses a disposable GitHub Actions PostgreSQL container with a fixed **test-only** password, no production secret, and no Noel live-db connection. Independently, the repo's existing Titus Formation Custody workflow may confirm source/custody continuity; neither workflow validates the future signed two-Person access membrane.

No production migration filename, database sync, Supabase secrets, public reader, auth grant, user account, Titus UI route, GitHub main merge, Preview or Production deployment is part of B2A.

## Necessary next B2B / B2C outcomes

Before any real writer:

1. **Prove learner attribution of the original.** `teacher_id` inside the existing Formation response is historical Titus teacher-profile identity, **not** a signed Person or reviewing instructor. Active `teacher_person_bindings` supports the existing self-learner model but cannot retroactively prove who submitted each older record; provenance and consent/retention implications need review.
2. **Prove a specific teaching edition and recipient entitlement.** A draft unit/packet, a program title, an Atlas session, a historical `primary_teacher` label or a fixture UUID is not a content-release receipt. Any material referenced by an actual student encounter must be rights-cleared and pinned to an approved edition.
3. **Resolve the actual reviewer Person/issuer/mandate.** Require a current valid authenticated session, actual program-steward or commissioned teacher authority to read exactly this learner's answer and submit feedback, exact source scope, reviewer revocation, independent disclosure rights and no self-review. Do not instantiate a second Titus/Atlas identity or a global `teacher` boolean.
4. **Design a reviewed source-owned command.** The caller supplies only exact Work/response, expected latest event, disposition and text; the server re-resolves all IDs and current actor/reviewer/rights; transactionally verifies the expected predecessor and inserts the feedback event. The corresponding learner revision command appends a new original Formation response and a link event in one transaction; no client-specified Person/release assertions.
5. **History and correction law.** The current underlying `formation_responses.raw_text` can be updated by privileged internal operations. True immutable-at-encounter learner history needs a separately approved original-response revision or source freeze/verification contract; this proposal only makes **the links/feedback events** append-only. Historical correction and legally required removal must be treated as distinct governed operations rather than silent table overwrites.
6. **Test real isolation.** On a production-shaped disposable clone with real local GoTrue/PostgREST signed sessions, prove one positive with legitimately issued test mandates and negative wrong reviewer, cross-program, wrong recipient, revoked grant, withdrawn learner relation, stale release, expired session, concurrency/replay and zero extraneous disclosure. No live user data and no production traffic.

### Completion status

- **B1 Titus:** validated *read-model only*, not published.
- **B2A Noel:** this proposed append-only *storage/lineage carrier* plus miniature PG structural proof; the current authority gate remains closed.
- **B2B:** reviewer mandate/read/disclosure and edition release proof **not implemented**.
- **B2C:** source-owned feedback/revision writers and signed end-to-end proof **not implemented**.
- **Builds C–E:** queued.

The larger real teacher/student learning workstream is not complete because this candidate passes its structural tests.
