# Shared Titus learner-private Course notebook v1 — source candidate

**Status:** Source-only, HELD / no live migration, no real access, no release.
**Custody:** Noel `shared_` source lane (Titus notebook records + Atlas Teaching enrollment + Reality Person + Auth). No duplicated enrollment, no new identity or private customer Course publication.

## One bounded result

A **private note original**, authored by a genuinely signed current Person enrolled in an **already-open Atlas Teaching Offering**, attached to that Offering's immutable published Course Version. The existing `atlas.teaching_enrollments` relation is the sole academic admission. An authored note is visible only to its originating Person via signed Titus self-read; a teacher, school owner, course author, reviewer, sibling enrollment, staff role or administrator has **no derived reader**. No teacher feedback, shared homework submission, classroom disclosure, Case Lab response, or published Course content is carried here.

The current Titus Song Keeper Course is `titus.customer_course_drafts_v1`, **not** `atlas.teaching_courses`. This candidate intentionally does not expose its text, issue a Teaching activation, publish a Course Version, open an Offering, enroll a Person or map a private author draft to academic Teaching. It must not be used as a shortcut to make a fictional learner notebook look source-backed.

## Exact authorization input

`public.titus_learner_private_note_create_self_api_v1(enrollment UUID, request UUID, body text)` and `public.titus_learner_private_notes_read_self_api_v1(enrollment UUID)` are the only proposed browser transports. No actor Person ID, Auth ID, Teacher ID, Ledger or Course ID is accepted from the client. The private guard derives the actor from `auth.uid()` and the existing live `titus.current_authenticated_person_entity_id_v1()`, which checks current Auth session and canonical Reality Person binding. It also demands one active canonical mapping, a confirmed nonanonymous user, the **exact registered Titus OAuth client**, and a matching active `atlas.person_auth_credentials` for that same Atlas Person. Equality of UUIDs alone confers no power.

A valid write/read additionally requires an exact, currently active `atlas.teaching_enrollments` row owned by that Person, an open/unretired Offering, active Course and Teaching capability, and the exact published Course Version. An unknown/foreign/withdrawn or expired-session case receives no note list and cannot write. We intentionally choose **no post-withdrawal self-read in v1**; the historical original remains preserved, and post-withdrawal private export/restoration rights need a separate source decision.

## Source operations

The only table is `titus.learner_private_course_note_events_v1`, with RLS and FORCE RLS, no direct anonymous/authenticated/service-role grants, original row immutability, 3,000-Unicode-character note bound, 100-notes-per-enrollment limit and an enrollment-scoped exact operation UUID. The writer locks the already-authorized Enrollment and rechecks its authority before insert; same request/body returns the original note ID, changed retry is denied. No `UPDATE`, `DELETE`, mutable resubmission or browser-local persistence. The self-reader returns only that Person's notes for that enrollment/source version, not other People, Course source bodies or a roster.

An event is a private note **only**. It is not a graded submission, teach-back, independent research source, or disclosure to any reviewer. Existing [held shared classroom PR #2474](https://github.com/optical-lift/noel-core-db/pull/2474) carries a *different*, source-consented shared homework stream; its writer remains hard false. Existing [held current-Person authorized home PR #2438](https://github.com/optical-lift/noel-core-db/pull/2438) is an institutional learner discovery reader, still not released. Neither held source is silently incorporated or replaced here.

## Verified live prerequisites (SELECT only, November 6, 2026)

The `noel-core` database currently reports 1 private Titus customer Course draft but **0 Atlas Teaching Courses, 0 open Offerings and 0 active Teaching Enrollments**. `titus.current_authenticated_person_entity_id_v1()` and `atlas.teaching_enrollments_for_current_person_self_api_v1()` exist. The held `public.titus_authorized_home_self_api_v1()` and `public.titus_classroom_read_self_api_v1(uuid)` are absent. These are read-only source observations, not a reason to seed a user or shortcut an entitlement.

## Test contract — UNVERIFIED until actual disposable PG17 run

First execute `candidate.sql` against a production-shaped **synthetic, isolated PostgreSQL 17 clone** in the `shared_` lane; then run `structural_postconditions.sql`. Required **genuine signed GoTrue/PostgREST** tests (not just synthetic GUCs) must prove:
1. Current nonanonymous Titus OAuth client, one canonical Person and exact already-enrolled active Offering: empty self-read, one note original, same-key same-body replay, exact original readback.
2. Later note creation, order and source edition remain specific to the same Enrollment.
3. Second enrolled Person cannot read or create a note for the first; teachers/owner/root governors have no inherited access without also being that learner Person.
4. Withdraw Enrollment, close/retire Offering, pause Teaching, retire Course, revoke Person or Auth binding, ban user, expire/remove session, wrong OAuth client and missing account each deny read **and** write with no existence disclosure.
5. Unknown/foreign Enrollment, another Course Version, modified duplicate operation, too long/empty content, missing operation ID, direct table SQL, anon and service-role RPC calls fail closed.
6. Concurrent same-operation attempts produce exactly one durable original; no direct UPDATE/DELETE, no reviewer disclosure, no unapproved shared classroom events.
7. Source schema exact ACL, RLS and FORCE RLS remain closed in the released schema even with PostgreSQL role grants inherited from surrounding sources; all scratch changes are removed.

**Not yet done:** disposable PostgreSQL source-shaped SQL execution, signed-session matrix, reviewer approval, exact migration generation, protected release, real Course Offering, actual enrollment, Titus app UI, visual acceptance, production. A static/source-CI result is *not* any of these approvals.

## Release boundary and next work

Review the shared schema candidate against current canonical main and source-held classroom/home decisions. Use no live SQL other than SELECT verification without separate owner approval. The protected migration requires an explicit source-governed approval naming target, exact version and release lane. The eventual Titus client may connect only after a real Enrollment exists and owner/learner access is independently accepted. Keep [Titus authoring PR #72](https://github.com/optical-lift/titus/pull/72) in draft; its editor and protected Preview are untouched.

## Source-only completion register — November 6, 2026

- **Exact executable-source commit:** `d22f919c65658ef2eacfcf4ada9fd7365205f717`. The candidate is four source-only files under `candidates/shared-titus-learner-private-notebook-v1/`; no migration, outside repository or product code changes.
- **Source static checks:** eight direct candidate invariants checked: source-only transaction and no synthetic enrollment seeding; active canonical Person and Titus client; exact existing Atlas Enrollment/Offering; no actor/teacher arguments; closed RLS/ACL; immutable original and replay; strict self-reader; no customer draft/classroom shortcut. These are static checks, **not** execution of the included Python test file or PostgreSQL.
- **GitHub custody:** [Database Custody CI #42322991224](https://github.com/optical-lift/noel-core-db/actions/runs/42322991224) **SUCCESS** on exact candidate commit, including repository custody rules. That CI is not source-specific PG17 runtime authorization.
- **Live source observation:** SELECT-only read returned 0 Teaching Courses, 0 open Teaching Offerings, 0 active Enrollments, and one unreleased private customer Course draft. No learner could actually pass the candidate's current permission predicate. The proposed APIs do not exist on production.
- **Remaining proof, all OPEN:** proper isolated production-shaped PG17 parsing/application; execute `structural_postconditions.sql`; fictional separately enrolled Person/outsider, idempotency, concurrency, expiry and withdrawal tests; genuine signed Titus OAuth GoTrue/PostgREST negative matrix; internal schema ACL/owner audit; shared-lane reviewer acceptance; exact migration and separately authorized protected release; independent real Titus browser proof. No person enrollment, consent, entitlement, or private note may be fabricated to satisfy a test.
- **Next unfinished step:** reuse the held shared source/identity fixture without importing the classroom writer as a reader or the institutional authorized-home candidate as a grant. Prove this exact SQL against a disposable PG17 clone with **two distinct current-Person sessions**. If the authentic shared source cannot prove the required enrollment, keep both writer and learner notebook closed. Do not merge because custody CI passed.

**Closeout status:** candidate filed, source checks and repository custody PASS, *runtime and release HELD*. No user-facing notebook is available yet.

