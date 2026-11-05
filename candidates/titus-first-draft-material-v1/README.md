# Titus first original Course material — held source candidate

**Date:** November 4, 2026. **Status:** SOURCE-ONLY DRAFT; not migrated/released, not authorized for production, not an entitlement issuer.  
**Owner:** Noel's `titus` source lane; Titus consumes guarded API only.  
**Dependencies:** Live released migration `20261104222535_titus_customer_workspace_first_course_v1` and its zero-seed customer tables and active-entitlement gate. Existing Titus draft PR [#49](https://github.com/optical-lift/titus/pull/49) implements source-confirmed blank-university and first-course creation. Governing: Titus blank-product constitution.

## One bounded outcome

Save **one original, private course manuscript text** without requiring any Program, Module, Lesson, Offering, teacher assignment, learner, research import, or publication. Each edit is an **append-only revision**, and the author may reopen the most recent source-confirmed revision. This is the first real material editor source; it does not claim to implement the entire university lesson/content system.

The source never installs curriculum, seeds a sample Course, infers an educational method, or migrates Marlene's research.

## Source nouns

- `titus.customer_course_material_revisions_v1`: append-only text revision, FK to the existing **customer draft Course**, exact Course-scoped request id, expected previous revision, revision number, author Auth user and durable timestamp. No destructive overwrites.
- `public.titus_customer_material_read_self_api_v1(p_course_id uuid)`: returns `{contractVersion:"titus_customer_material_v1",courseId,material:null}` before authoring or `material:{revisionId,revisionNumber,text,savedAt}` for the latest real revision. Returns an error for other/missing Course IDs, not their titles.
- `public.titus_customer_material_save_self_api_v1(p_course_id uuid,p_request_id uuid,p_expected_revision integer,p_text text)`: appends exactly one original revision only when current revision matches; idempotent same-request replay; conflicting replay and stale expectations denied. Max 40,000 characters, 10,000 revisions, 0-length text permitted.

## Authorization boundary

Both RPCs call released `titus.customer_current_auth_user_v1()`. That function requires a current, confirmed, nonanonymous GoTrue session and an active source-issued buyer/private-pilot entitlement. A browser cannot specify the acting owner. The actual Course must be in the current user's own `titus.customer_workspaces_v1`; writes also require active (not suspended) workspace. A known Course UUID alone is not authority.

The new table has RLS enabled, no end-user direct table grants, no `service_role` table read/write grant, and the two narrow public SECURITY DEFINER functions have `EXECUTE` granted only to `authenticated`, not `PUBLIC` or `anon`. Those privileged functions require independent source/security review before any potential release. They do **not** create entitlement or people, and the tests are not evidence that source-issued grants exist.

## Tests, ownership, and protected scope

- `fixture.sql` from the existing customer source creates **fictional GoTrue-like rows** and unsigned session claim GUCs **on a brand-new isolated PG17**. It is NEVER production-safe and must never run on a production-shaped clone without a separate source-approved adaptation.
- `candidate.sql` is loaded after that existing, released customer source candidate into scratch.
- `postconditions.sql` proves zero seeded content, RLS/zero direct grants, non-entitled denial, new blank body, first save and reopen, exact request replay, conflicting request denial, stale revision denial, append-only revision preservation, outsider read/write denial, revoked entitlement denial, expired session denial and input-size denial.
- `scripts/test-titus-first-material-riversong-pg17.sh` uses one **fresh** PostgreSQL 17 cluster over private Unix socket 55449, not Atlas 55432 or the separate customer-course 55447. Source and test runner delete only their own scratch files.
- `.github/workflows/titus-first-draft-material-pg17-riversong.yml` checks out exact Git SHA in an isolated workdir and runs this scratch proof. No GitHub merge or production migration is triggered by a test pass.

## Explicit non-goals

Not a Course `Edition`, published Lesson, source-canonical Song research, learner experience, institution permission delegation, billing, teacher enrollment, multiple authors, file upload, lesson hierarchy, or actual production authorization.

Not a universal model of institutional membership. The prior private single-owner source remains a first-run nucleus only; general institutions must use Atlas/Noel canonical Person/Ledger authority rather than hardcode Auth user ownership as their final form.

## Completion register

| Gate | State |
| --- | --- |
| Genuine live customer source migration, no-seed | **Confirmed already released** [Noel issue #2484](https://github.com/optical-lift/noel-core-db/issues/2484), run [#41929072140](https://github.com/optical-lift/noel-core-db/actions/runs/41929072140). Read-only 2026-11-04 confirmation: 3 customer tables/RPCs, one migration receipt, RLS true, **zero** workspaces/courses/entitlements |
| First material source candidate | **Implemented in this held branch**, not merged |
| Independent PG17 fictional-owner verification | **Pending** until exact RiverSong receipt |
| Source security/custody review | **Not performed** |
| Production-shaped clone + generated reviewed migration | **Not performed** |
| Authorized live release / feature flag | **Not performed** |
| Actual buyer/pilot grant issuance | **Not implemented** |
| Real signed Auth owner + outsider browser acceptance | **Not performed** |
| Titus authoring UI/API / preview | **Not implemented by this source-only increment** |

**Next:** Pass isolated PG17, then build a default-OFF Titus authoring client/API against precisely this source contract; separately review source/custody and build a genuine private-pilot grant issuer. The user must explicitly authorize any live migration/release. Do not manually insert a pilot entitlement merely to obtain a screenshot.
