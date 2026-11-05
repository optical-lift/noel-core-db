# Titus owner-designated private-pilot tester — issuance completion register

**Owner request:** 2026-11-04, `lexprjct@gmail.com` should receive the legitimate Titus entitlements needed to test all existing released capabilities.  
**Authorization receipt:** [owner-authored issue #2489](https://github.com/optical-lift/noel-core-db/issues/2489).  
**Source-owned scope:** Noel `titus.customer_workspace_entitlements_v1`, existing live table from migration `20261104222535_titus_customer_workspace_first_course_v1`.  
**State:** SOURCE-ONLY issuer code in this draft branch; no entitlement issued or migrated by the code. Do not equate owner request with SQL execution.

## Live facts verified by read-only SQL

- Exactly one `auth.users` account matches the supplied email, confirmed, nonanonymous and undeleted on the check. Account eligibility must be rechecked at the instant of issuance.
- Existing `titus.customer_workspace_entitlements_v1` accepts `private_pilot` or `purchase`. **No purchase can be fabricated for testing.**
- No entitlement exists for this account at audit time. Live workspace, draft-Course and entitlement tables were all zero records.
- `authenticated`, `anon`, `service_role` have no direct INSERT/SELECT on the entitlement table. This is deliberate. **Never grant them broad permissions** to make issuance easier.
- An active `private_pilot` already satisfies the released customer's source reader/writers (catalog, start empty university, first draft Course) for a confirmed current session, and will satisfy the separately held draft-material writer only when its source release gate is passed.
- Classroom participation, teacher mandates, learner enrollment, Formation reviewer access, Marlene editorial admission, Atlas organization roles, administrative controls and publishing have **distinct sources**. One private-pilot purchase-equivalent customer grant does not confer those powers, and this owner request does not authorize fictitious teachers/students or unrelated accounts.

## Proposed protected issuer (no automatic deployment)

- `scripts/titus-private-pilot-issue.sql`: **one data transaction**, not a migration. Existing `auth.users` exact email check (unique, confirmed, live, nonanonymous, not banned/deleted); verifies reviewed owner issue receipt; creates at most one 1–180-day `private_pilot` row. Exact owner receipt replay is idempotent. A changed receipt, purchase, suspended/revoked/expired prior grant, second account, or bad input fails closed. One transaction, short lock/statement timeouts. No workspace, Course, Auth user, Person role, or source permission is created.
- `scripts/verify-titus-pilot-approval.py`: requires exact open issue authored by GitHub repository **OWNER**, matching title, target email, `private_pilot` not `purchase`, trusted GitHub issue URL and explicit body authorization.
- `.github/workflows/titus-protected-private-pilot-issuance.yml`: **workflow_dispatch only**, main branch only, `environment: production`, exact project confirmation, existing protected Noel database URL, verified issue and custody checks, exact account and duration. No automatic push or issue event can issue a grant. Production request must be separately dispatched and protected environment approved **after** source review and merge.
- `tests/test_titus_private_pilot_approval.py`: synthetic issue verification and guard assertions.
- `scripts/test-titus-private-pilot-issuer-pg17.sh`: disposable RiverSong PostgreSQL 17, fake Auth accounts only. Tests actual SQL creation, idempotence, wrong target, conflicting receipt, unknown account, malformed request, 180-day maximum, deleted/failed confirmation and revocation. Uses private socket **55452**, distinct from protected Atlas **55432** and customer scratch **55447**. No production credentials or live SQL.
- `.github/workflows/titus-private-pilot-issuer-riversong.yml`: isolated test job, no production connection or protected secrets.

## Acceptance sequence (independent gates)

1. [ ] OWNER email issue #2489 exact author and title verified (read-only).
2. [ ] Source code reviewed for narrow private Auth/account and entitlement scope, no exposed table rights, denial/idempotence/revocation.
3. [ ] RiverSong PG17 test run PASS at exact source SHA, plus Python issue-verifier tests.
4. [ ] Source custody/CI PASS, no existing production source modification, no new migration.
5. [ ] Source PR approved/merged to canonical Noel `main` (separate action; not authorized by CI alone).
6. [ ] Owner explicitly approves and manually dispatches the protected production issuance workflow with `owner_issue_number=2489`, `target_email=lexprjct@gmail.com`, `valid_days=180`, exact Noel production project ref. This has financial/non-research meaning **private pilot**, not purchase.
7. [ ] Live read-only check: exactly one active private_pilot row for the existing user with the source issue receipt and bounded expiry, no workspace/Course/other-user entitlement changes.
8. [ ] Real signed positive owner/negative outsider app test. No fabricated Auth account or bearer tokens.
9. [ ] Revoke/renewal route documented and independently source-approved before periodic use.

## Protected and unresolved

- **NOT** to be run as generic `Supabase.execute_sql` production mutation or as an ad hoc data seed in a schema migration.
- No application source flags or deployment changes. Titus [#48](https://github.com/optical-lift/titus/pull/48), [#49](https://github.com/optical-lift/titus/pull/49), [#50](https://github.com/optical-lift/titus/pull/50) are independent held UI changes; Noel manuscript source [#2488](https://github.com/optical-lift/noel-core-db/pull/2488) remains a separate held release.
- No blanket superadmin or other human's data access. All future new Titus capabilities must independently establish canonical rights; do not issue speculative entitlements.
- If tests fail, maintain the grant table at zero and fix only this reviewed issuer path. Technical availability of a privileged SQL tool does not create permission for a shortcut.

## Closeout

- Requested: authorize the exact account for full *legitimate* Titus testing.
- Changed in this branch: source-controlled issuer, OWNER verification, default-off manual protected workflow and disposable tests. Owner issue #2489 created.
- Live state: **no entitlement issued** as of the read-only inventory.
- Next unfinished: source tests, independent review, protected release and verified actual receipt. Do not declare the user enabled until all succeed.
