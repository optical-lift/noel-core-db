# Titus private customer workspace + first Course — completion register

**Date:** 2026-11-04. **Status:** bounded source candidate only; not a migration, not applied.  
**Owner of structural source:** Noel; owning product: Titus.  
**Scope:** zero-Course customer workspace, source-owned draft Course and owner-only list/append.  
**Companion app:** [Titus draft #46](https://github.com/optical-lift/titus/pull/46) stacked on independent empty shell [#45](https://github.com/optical-lift/titus/pull/45).

## Existing nouns kept distinct

The inherited `titus.courses` table contains historical curriculum/reader Courses with a global `course_slug` and **no customer workspace owner**. Do not graft arbitrary buyers' content into it or automatically import protected Dr. Marlene/Noel/Formation research. Atlas `teaching_courses` and `teaching_course_offerings` describe activated Teaching capabilities/offerings; they are **not** product login prerequisites.

This candidate introduces separate private, customer-scoped draft nouns:

- `titus.customer_workspaces_v1`: one durable workspace keyed by a current nonanonymous, confirmed Auth user; allowed to have zero Courses.
- `titus.customer_course_drafts_v1`: one original user-created Course title in draft state, owner/workspace-linked, create-request idempotency.
- Three narrow `public.titus_customer_*_self_api_v1` RPCs: current owner's read, explicit workspace creation, explicit first draft Course creation.

No Course, Person, learner, university, purchase/entitlement, or unpublished research row is seeded. Underlying tables have RLS enabled and no authenticated/anon direct privileges. Each privileged RPC rechecks `auth.uid()`, confirmed nonanonymous `auth.users` and current `auth.sessions` with the signed JWT session id, checks current source owner and does not accept caller-supplied workspace/Person/owner identifiers. Public SECURITY DEFINER RPC boundary requires source/security review before release; functions are revoked from PUBLIC, with explicit only authenticated execution.

## Acceptance checks

| Test or gate | Current state |
| --- | --- |
| Signed new user's catalog legitimately `workspace:null,courses:[]` | Source and fixture written; PG17 result pending |
| Create private workspace, still zero Courses | Source and fixture written; PG17 result pending |
| Append original draft Course; second read returns same Course | Source and fixture written; PG17 result pending |
| Reusing original request ID does not duplicate; conflict rejected | Source and fixture written; PG17 result pending |
| Another signed buyer cannot see or mutate first buyer's Courses | Source and fixture written; PG17 result pending |
| Expired/revoked session denied, no direct table grants | Source and fixture written; PG17 result pending |
| Single scratch-only RiverSong PG17 proof | [Titus carrier run #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), pending |
| Titus Node contract/Next no-release build | [Titus run #41919951401](https://github.com/optical-lift/titus/actions/runs/41919951401), pending |
| Production-shaped schema-clone review and governed Titus lane assessment | NOT DONE |
| Auth-signed owner/outsider production API smoke check | NOT DONE |
| Generated migration, source merge, protected release, feature flags | NOT DONE |
| Paid customer entitlement and billing/checkouts | NOT IMPLEMENTED; DO NOT CLAIM |
| Lesson editor, module builder, publication or actual teaching | NOT IMPLEMENTED by this increment |

## Security and release ordering

This changes only Titus-owned private tables and public self-APIs. Proposed classification is a **`titus_`** structural migration because it does not change Atlas, Reality, or other domain semantics, but Noel source-custody must approve the exact lane before generation. Canonical generator requires candidate merged to Noel `main`, an owner-issued exact generation request, disposable production-shaped clone proof and protected production release. No direct Supabase `execute_sql` or `apply_migration` to production during development.

The fake `auth.jwt()` and `auth.uid()` functions exist **only** in `fixture.sql` to exercise source behavior; they do not verify a JWT cryptographically. Only real GoTrue/PostgREST can do so.

The app must keep `TITUS_CUSTOMER_CATALOG_ENABLED=false` until source and operational release are approved. When enabled, public use without a genuine paid-customer entitlement would allow ordinary confirmed Auth users to create customer workspaces; do **not** advertise this pilot as a gated paid SaaS. Entitlement issuance must be its own source-authorized step.

**Next unfinished practical step:** once source code review and scratch PG proof pass, run a true production-shaped schema-clone validation, then request source generation/release. If releasing only the data-free shell, keep this source feature OFF. After source release, use a real signed owner and unrelated user for one positive/negative smoke test before enabling customer creation.
