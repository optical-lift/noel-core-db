# Universal Personal Atlas Implementation Case — candidate, NOT a migration

**Scope:** reviewed shared identity + Atlas implementation-origin candidate for [#1545](https://github.com/optical-lift/noel-core-db/issues/1545) and [#1546](https://github.com/optical-lift/noel-core-db/issues/1546), reflecting accepted Atlas Product Map `PMD-027`.

This candidate makes the existing `atlas.implementation_cases` represent **a verified human's Personal Atlas implementation** with no fake Stripe purchase, while preserving paid institutional setup and its real purchase/entitlement constraints. It does not create a new parallel personal case store, Ledger, Person or practitioner. The first-time Personal Atlas entry command admits the **existing** legacy Person/verified credential with their exact UUIDs to canonical Reality identity, and creates exactly one personal case in the same authenticated transaction. An existing Principal takes that same governed admission path; no unconditional early return.

**Case identity:** `case_origin='personal_atlas'` requires a canonical Person and NULL purchase; `paid_institutional` requires a real existing purchase and NULL personal subject. A partial unique index permits one personal case per canonical Person across retries and sign-in sessions. A separately authorized user with a Personal Atlas entitlement can idempotently reconcile their own case via the self RPC. No fixture has anyone's real email, user ID, case UUID, task or Discovery answer.

**Read layer:** Existing `implementation_workbench_self_api_v1` and `implementation_case_self_api_v1` are unchanged for existing paid consumers. New `v2` reads show personal origin and explicitly nullable purchase. The Workbench admits only separately authorized Atlas practitioners. It returns person display name and case state, **not** private Bookplate, household, answers or task contents. `atlas_handling` means not currently assigned a practitioner, not a claim that the person's implementation is complete.

**Boundaries:** This candidate does NOT automatically close cases after one task/answer, declare a household fully implemented, create institutional authority, bypass the separately signed-in Workbench, fabricate a purchased entitlement, or charge Stripe. No real-user backfill occurs in the schema migration: that is a separate authorized and audited Atlas data transaction.

**Synthetic enrollment integration fixture (v3):** `fixture.sql` sets up three clone-only verified Auth credentials: a fresh user with a claimed complimentary invitation, an already-established legacy Principal with a valid grant, and an unentitled user. `postconditions.sql` runs both real `begin_personal_atlas_self_api_v1` paths, retries them, checks exact Person/credential preservation and unique personal cases, verifies no fake purchases/Ledger entitlements, and denies normal-user practitioner visibility and unentitled onboarding. The data and actions execute **only** inside the disposable local production-schema clone.

## Review and release sequence

1. Exact source review for current identity/case contracts and `shared_` migration lane.
2. Generate migration identity only through `.github/workflows/migration-source-generation.yml` after reviewed candidate merge.
3. Run disposable production-schema clone with `postconditions.sql` and fixture-backed cases: new and established entitled users, repeated/concurrent calls, two different people, expired/missing access, credential collision, canonical binding conflict, unchanged paid checkout, paid+personal V2 reads, native Personal Atlas trigger, unauthorized readers and private-data boundary.
4. Update Atlas frontend to V2 Workbench and Case readers, rendering `personal_atlas` without misleading Purchased/activation claims. Database before app release.
5. Manual protected DB release of exact migration. Then separately verified authorized Atlas data reconciliation of existing people, no public row-bearing SQL.
6. Verify one real Personal Atlas user appears on practitioner Workbench with no new role or purchase; verify prior paid two-Ledger implementation still works.
7. Add actual evidence-backed autonomous quiet completion only after domain source receipts and necessary authority have been established. No synthetic completion percentage.

**Status:** Candidate source only. No production schema/data mutation; further clone proof and app consumer integration required.
