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
| Signed new user's catalog legitimately `workspace:null,courses:[]` | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Create private workspace, still zero Courses | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Append original draft Course; second read returns same Course | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Reusing original request ID does not duplicate; conflict rejected | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Another signed buyer cannot see or mutate first buyer's Courses | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Expired/revoked session denied, no direct table grants | **PASS — [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840), exact source SHA `955a9a9de95198ca511b4e907f3957e2ccee5d80`** |
| Single scratch-only RiverSong PG17 proof | **PASS** [Titus RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840) |
| Titus Node contract/Next no-release build | **PASS** [Titus RiverSong #41919951401](https://github.com/optical-lift/titus/actions/runs/41919951401) — 15/15 tests, scoped ESLint, no-deploy Next build, cleanup |
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

## Verified source closeout — 2026-11-04

**PASS:** [RiverSong #41919987840](https://github.com/optical-lift/titus/actions/runs/41919987840) on exact executable source/fixture/runner commit `955a9a9de95198ca511b4e907f3957e2ccee5d80` (Titus carrier `4ddd58abdd9e8f396d6d36d83d2ba8add6b395d4`). One newly initialized **disposable PostgreSQL 17** instance on private socket port **55447** (never protected Atlas clone 55432) loaded `fixture.sql`, then this actual single-transaction source candidate, then `postconditions.sql` and exited successfully. Verified new owner empty read, explicit workspace remaining empty, first draft Course original, replay idempotency/conflict, unrelated buyer isolation, no direct table grants, and live-session expiry denial. The scratch `auth.uid()/auth.jwt()` functions read **unsigned invented test claims**; this is a SQL-source behavior proof, NOT real GoTrue signature verification. No production schema/data/permissions were changed. Isolated runner checkout and scratch database cleanup passed.

**Independent application proof:** [Titus RiverSong #41919951401](https://github.com/optical-lift/titus/actions/runs/41919951401), exact app source SHA `dffe8e8fe6422e127d851473647035dd659061ad`, **15/15 Node tests PASS, ESLint PASS, Next build PASS (15/15 static pages), workspace cleanup PASS**.

**Closed:** bounded draft source candidate and its scratch source proof. **Open:** production-shaped clone; explicit source/security review and Titus lane classification; migration source generation, main merge, protected production release; a real owner/outsider signed smoke test; paid entitlement; real private-use launch. This README-only update does not change executable source bytes after verification.
