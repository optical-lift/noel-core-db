# Atlas Build 5 — Eliminate Employee-Seat Authority (source contract)

Status: Implementation gate; **not a production migration or removal receipt**.
Owner: Atlas. Structural source: optical-lift/noel-core-db. Companion UI: optical-lift/atlas.
Decision date: 2026-10-20.

## Required invariant

A canonical Person is connected to a native Ledger by an active `ledger.seats` relationship. Employment, contracting, kinship, and volunteering are optional descriptive attributes of that relationship, **not different identity, admission, access, work-responsibility, or execution mechanisms**. A connected Person can exist without an Atlas login. A login credential gives a means of authentication, not jurisdiction, authority, employment, or billing entitlement.

Different permissions and continuing obligations derive only from their actual bounded Ledger/Person relationship, independently established responsibility and accepted standing scope, plus the specific operation's authority rule. A seat alone does not give financial, owner, or generalized institutional authority.

Two distinct operations are required:
- **Offer Work** asks a connected Person to accept or decline a specific existing Work item.
- **Assign Work** attaches an existing Work item to a Person under an already established and currently effective responsibility/standing agreement. Do not create an offer or require new acceptance per item. Do not presume acceptance of an underlying standing scope.

Do not fabricate agreement, Work completion, reading receipt, a Worker Day, date placement, or task duplication. Preserve canonical Work IDs and original evidence.

## Production audit, 2026-10-20

- `atlas.organization_employee_seats`: exactly 1 live row, for the affected existing test Person.
- `atlas.organization_member_credentials`: exactly 1 row with an `employee_seat_id`, pointing to the affected test Person's seat. FK currently **ON DELETE CASCADE**.
- `atlas.company_work_standing_assignment_scopes`: 0 rows.
- the affected test Person already has an active native Flower `ledger.seats` connection, and her own active Personal Atlas complimentary-testing grant.
- a second existing connected canonical Person has active Flower and Venue Ledger connections but no member/Position dependency suitable for the old standing-scope implementation.
- Additional connected People without memberships must also be covered.
- Exact organization and Ledger identifiers must be resolved from the authorized source at test time, not hardcoded as personal fixtures.
- Existing employee-seat joins are in `atlas.organization_access_physical_compatibility_internal_v1`, `atlas.company_work_execution_membership_check_v1`, `atlas.company_people_native_ledger_scope_self_api_v1`, `atlas.organization_company_work_people_api_v1`, other employee-context / invitation RPCs; standing-scope RPCs require membership and appointment.
- Atlas UI still checks `employeeDeliverySeatState` for legacy employee offers and direct assignments, in `app/useCompanyNotebookSpreads.tsx` and `app/CompanyWorkStandingScopeOwnerPanel.tsx`. `app/EmployeeInvitationPanel.tsx` uses a billing-oriented employee invitation path.
- `atlas.connected_person_company_work_today_self_api_v1` currently only selects allocations with `establishment_basis_kind='person_connection_receiver_uptake'`; it will **not** show new directly assigned standing-scope allocations unless updated.

These are audited current-state facts, not a declaration that the existing implementation has been removed.

## Implementation sequence (must be enforced, not merely documented)

### 1. Create a verified, seat-independent access membrane

Replace the source of institutional notebook access with authenticated canonical Person identity + exact active Ledger connection + independently authorized Ledger scope. Keep organization-wide owner/management rights bounded to their already established governing grant: a Ledger seat by itself MUST NOT create management or financial access.

Preserve the affected test Person's current credential row, auth-user binding, principal, personal grant and historical membership/appointment references. First remove the credential-to-employee-seat FK dependency by rewriting the relevant authorization functions and modifying the credential schema in a governed migration. The actual employee-seat row is not the login identity. Do not expose cross-Ledger or private Personal Atlas information. Positive and negative tests must include owner, the affected test Person, the second test Person, disconnected person and accountless person.

### 2. Move established standing responsibility onto native Person/Ledger authority

Reuse existing `ledger.seat_responsibilities` and `reality.responsibility_relations` where their released contracts fit. Inspect their full DDL and authorization/uptake rules before deciding whether to extend `atlas.company_work_standing_assignment_scopes` or replace its membership and Position-appointment dependency. Canonical Person, exact Ledger, bounded duty/scope, issuer, acceptance evidence, effective interval and revocation must be verifiable.

Native standing agreements support two explicit responsibility boundaries:
- `operation_class`: one recorded operation class in one operating unit. Assignments outside both must fail.
- `ledger_all_work`: ongoing operational responsibility for every exact-source Work item relevant to that Ledger, including older recovered Work with no class or unit. The receiver must expressly accept the breadth of this single agreement. It is **not** a grant to see finances, administer access, or act as owner; only already-authorized Work assignment is possible.

A production read-only audit found that most recovered Work in one existing Venue Ledger currently has null operation-class and unit fields. Do not fabricate those classifications merely to permit assignment; use an openly described Ledger-wide agreement when genuinely authorized, or leave the Work unassigned.

An existing relationship is not proof of consent to new duties. Where one-time acceptance is required, the actual Person must accept the scope. No implicit acceptances or acceptance attributed to the owner. Existing standing-scope table is empty, so there is no standing-scope row history to rewrite.

### 3. Canonical direct assignment and the recipient notebook

Extend the existing `manager_assign_company_work_under_standing_scope_self_api_v1` semantics through a new or versioned RPC once the standing basis is canonical. Validate original Work ID, exact native Ledger relevance, issuer's bounded assignment authority, active worker connection, accepted scope, scope-matching duty and time, no conflicting responsible allocation, and no unanswered offer. Lock Work and create exactly one `atlas.work_allocations` responsible allocation with canonical assignee Person and evidence of `delegated_under_standing_scope`. No per-task offer, no duplicate Work.

Update `atlas.connected_person_company_work_today_self_api_v1` or its successor to include directly assigned Person-native allocations, not only receiver-uptake offers; surface **Assigned** separately from **Scheduled Today**. Ensure ordinary Done/Blocked/Unfinished reporting obeys the Work's result contract and retains performer, reporter and review distinctions. Reassignment and revocation must preserve original Work and allocation history.

Companion Atlas UI: visible simple **Assign Work** and optional **Offer Work** actions on a Work record; Person picker uses canonical Ledger connections; standing scope configured in People without employee membership/seat; no duplicate question per task. Remove employee-only navigation and selectors after successor RPC is released.

### 4. Remove the legacy system physically, after safety gates

Audit all `pg_depend`, `pg_constraint`, `pg_proc`, triggers, policies, public grants, indexes, imports, tests and repository references to employee-seat paths. Replace them or drop obsolete functions and routes in dependency order. Drop `atlas.organization_employee_seats` and its obsolete employee-only triggers/functions/constraints/columns, including its one legacy row, **only after** a zero-user-disconnection test proves the affected test Person's signed-in Ledger access, account, responsibility, credential and Personal Atlas entitlement remain unchanged. Do not use `DROP ... CASCADE` as a shortcut. Do not delete `atlas.organization_member_credentials`, `auth.users`, `atlas.principals`, historical `atlas.work_allocations`, or Person identities.

Preserve historical evidence in the original surviving canonical records; do not keep the obsolete employee seat as an archived/renamed/disabled table. Employee terminology must remain only where reporting a historical factual employment relationship, not as authority or a paid seat concept.

### 5. Required verification before saying complete

1. Read back the affected test Person's account, personal access grant, Flower native seat, credential, Farm Steward duties, existing allocations/results and login access after migration.
2. Read back the second test Person's unique canonical identity and both Ledger seats. Establish his Venue standing responsibility through legitimate uptake rather than invented acceptance.
3. Assign **one existing recovered Venue Work item** to the second test Person under an accepted standing scope. No fresh Accept/Decline question, exactly one responsible allocation, no Work ID change.
4. Confirm the same Work is visible in his notebook even if not scheduled for Today; when scheduled, correct Today projection. Confirm Done/Blocked and independent acceptance on the source Work, no fake execution receipt.
5. Test revoked scope, wrong Ledger, non-manager issuer, absent login, conflicting offer and duplicate/retry denial. No money/finances exposure.
6. Prove `to_regclass('atlas.organization_employee_seats') is null`, no executable references remain, and the affected People share the same connection model in UI.
7. Provide separate receipts for source PR, schema-clone validation, source merge, protected migration release and explicit Atlas production deployment.

## Custody and release

This file is a source contract / implementation tracker. It is **not** SQL and cannot authorize production mutation. Any schema/function/RLS/GRANT changes belong in reviewed `atlas_` candidate source and generated migration via `noel-core-db`, disposable-schema clone validation, and explicit protected release (see `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md` and `docs/PRODUCTION_DATABASE_RELEASE.md`). Atlas application source belongs in `optical-lift/atlas` and does not deploy on merge. No production SQL, release workflow, Vercel setting or auth principal is changed by this document.
