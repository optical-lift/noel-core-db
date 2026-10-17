# Titus Author Studio — isolated verification and release gates

**Status:** Source proposal only, not a Supabase migration or deployment authorization.
**Source under test:** `architecture/proposals/TITUS_AUTHOR_STUDIO_READ_SAVE_V1.sql`.
**Application source:** `optical-lift/titus` branch `work/titus-author-studio-session1-20261016`.
**First unit:** Module 1, Session 1; existing `titus.formation_units` and five draft `formation_unit_sections`.

## A. Required migration preparation

In an authorized local checkout of `optical-lift/noel-core-db`:
1. Resolve canonical migrations/main release tail and verify the October 3 formation kernel remains immutable.
2. Use the supported Supabase CLI `migration new` command to create a new `titus_...` timestamped migration. Do not manually invent a timestamp. Copy/adapt the reviewed proposal into that migration; avoid duplicate previously implemented authority.
3. Run the exact schema and security tests in a disposable database, not a hidden production release.
4. Inspect security advisors, function grants and the Data API exposure profile. Both `titus` private tables must be RLS-on/no direct `anon` or `authenticated` rights. End-user access to the two `public` RPCs requires active verified Atlas Auth/Reality Person and active *program-author* grant.
5. Source review, PR/custody checks, explicit release approval and exact-version manual release are separate actions. Do not enable browser preview or production as a validation shortcut.

## B. Positive proof cases

- Create disposable test program, person and active program-author grant with explicit test identity; do not seed real Marlene or project owner automatically.
- Authenticated granted author reads `mcmillan-university` / `m01-s01`; result is `ready` with syllabus slots, Session 1, its existing unit, all five draft sections, attached historical-source candidates and questions. No learner-ready filter is applied to the author view.
- Edit a **draft** section with a matching `updated_at`; assert `saved`, changed existing row, exactly one `formation_section_edit_events` record containing previous and new text, same unit/section ID and same `draft` status.
- Reopen/reload the read RPC and verify the new text and a new `updatedAt` are returned. Then save with the **previous** timestamp; assert `conflict` and no further changes/audit events.
- Save same unchanged text with current timestamp; assert `unchanged`, no new history record. Verify two sections cannot be changed by a single RPC call or broad UPDATE.

## C. Mandatory negative proof cases

1. No bearer/anonymous, expired, revoked or foreign OAuth session: no author material, no mutations.
2. Authenticated Person with no grant: no draft source disclosure or save. Teacher-person binding alone does not grant builder permission.
3. Active author grant for *other program*: cannot read or update McMillan program. Program authorized for McMillan cannot edit another program.
4. Revoked/expired grant, retired Reality Person/invalid binding: no reads or writes. Current `current_authenticated_person_entity_id_v1` behavior must be reviewed for retired identities.
5. Section ID from a different program, random UUID, or a reviewed/approved section: no edit or leakage.
6. Unit no longer `drafted`: deny ordinary text Save pending separate authorized revision lifecycle.
7. Missing/blank/oversized heading or body, missing timestamp: reject without mutation.
8. Concurrent writer with stale timestamp: reject and preserve the latest text and audit trail.
9. SQL caller cannot directly select, insert, update or delete program grants/edit events using `anon` or `authenticated`.
10. No ad hoc service-role bypass, synthetic `auth.uid`, Person auto-matching by name/email, class publication, teacher readiness, or enrolled students.

## D. App-side proof

In an authorized local checkout of the Titus branch:
```sh
npm ci
npm run test:identity
npm run test:studio
npm run lint
npm run build
```
The app currently uses existing shared Titus OAuth behind `TITUS_ATLAS_OAUTH_ENABLED` and the independent `TITUS_BUILDER_STUDIO_ENABLED`. Neither is activated by this source. No Vercel deployment is allowed as test infrastructure.

Run a browser acceptance only after an individually authorized protected Preview and genuine test author grant:
- Sign in as the real owner Person (not the Marlene teacher source identity), see 15 sessions.
- Edit existing Session 1 draft, click Save, see canonical `saved`, reload, verify exact text.
- Click Discard unsaved changes and verify draft is unchanged.
- Open Session 3: see missing-packet research state rather than fake editorial content.
- Check wrong Person and wrong program requests are denied before any private HTML containing materials.
- Ensure neither Save nor source inspection changes `course_status`, `lesson_packet.status`, `formation_state`, `review_state`, learner `formation_responses` or any `teacher_person_bindings`.

## E. Verified partial proof before deployment

On 2026-10-16, the live DB received only a **transactionally rolled back** update to the `recognize` draft section under Session 1 using its current `updated_at` as a concurrency condition. The statement reported one matching row. A subsequent live read confirmed exact unchanged heading, `draft` state and unchanged source timestamp (`2026-10-17 02:05:03.396807+00`). This does **not** test the proposed author authorization RPC or a browser save: they remain unreleased.

Do not claim end-to-end author Save/reload before B–D pass on reviewed source and authorized deployment.
