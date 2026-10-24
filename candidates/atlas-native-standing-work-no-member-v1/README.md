# Eliminate organization member gates in the already-native Ledger work path

**Status: SOURCE ONLY; not released.** This is the second cross-domain slice of Atlas's universal Person cutover, after Foundry reviewer discovery. It modifies *actual standing work assignment*, not merely the Foundry UI.

## Existing contract
`atlas.company_work_native_ledger_owner_self_v1(organization, ledger)` already demands a signed canonical Person/Principal, an active exact native Ledger participation, and separate root-governing Principal/Ledger authorities. It does not infer Ledger governance from employee, consultant or member labels.

`atlas.propose_native_ledger_standing_scope_owner_self_api_v1` and `atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1` **then unnecessarily demand an additional `organization_memberships.role='owner'` record**, excluding otherwise lawful native Ledger governors. `proposed_by_membership_id` is NOT NULL despite having `proposed_by_person_id`. `work_allocations.assigned_by_membership_id` and `company_work_result_contract_bindings_v1.actor_membership_id` are already nullable.

## Narrow rewrite
- Allow `company_work_standing_assignment_scopes.proposed_by_membership_id` to be NULL (no historical values altered, foreign key preserved).
- Two native APIs use verified native Ledger governance rather than `current_effective_organization_membership_v1`; they continue recording the real `proposed_by_person_id`, Ledger, exact scope, accepted state, source, and decision audit.
- The `delegated_under_standing_scope` Person-native branch of `guard_work_allocation_responsibility_establishment_v2` now authenticates the current initiating Person and confirms they retain root governing authority on the exact native Ledger, rather than testing `organization_memberships.role='owner'`. New Person-native allocations have a NULL `assigned_by_membership_id`; historical old allocations can retain their original receipt.
- The old membership-based branch remains as a *legacy history/compatibility path* while consumers are migrated and regression-tested. This is not permission to create a new different Person subtype.

## Test and rollback obligations
Protected no-cost production-schema clone, this postcondition, and genuine signed owner/worker/stranger UI and API acceptance are required before production release. A current governor with no organization membership should be able to propose accepted standing work and assign an exact relevant open task. A connected person with no root governor grant must be denied proposals; work must require the receiver's standing acceptance; revocation must stop future direct assignment. Existing tasks, provenance, results, service-day evidence and communication contracts must remain unchanged.

**No runtime proof or production release is claimed by this source-only PR.** There is no paid environment or database DDL outside controlled local validation.
