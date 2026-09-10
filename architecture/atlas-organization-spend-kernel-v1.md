# Atlas Organization Spend Kernel v1

**Status:** Candidate architecture  
**Scope:** Canonical organization-owned spend occurrence and purpose allocation facts  
**Pilot:** Camps International / Los Domos expense reporting  
**Database authority:** `noel-core-db`

## Purpose

Atlas needs a universal money fact beneath reimbursement forms, accounting exports, budgets, project costing, and organization-specific expense categories.

The kernel answers only this question:

> What value was actually spent for organization purposes, by whom, to whom, when, in what currency, and what was it for?

It does **not** decide how an organization later classifies, reimburses, books, budgets, taxes, or reports that spend.

The governing sequence is:

`source/evidence -> spend occurrence -> purpose allocation -> organization ledger projection -> reporting/accounting interpretations`

## Why the kernel is not called the accounting ledger

A purchase can exist before anyone knows its QuickBooks account, reimbursement treatment, grant code, tax treatment, or Camps International category. Those are downstream interpretations.

The spend kernel therefore preserves operational money reality without becoming a general ledger.

For the Camps International pilot:

- David personally paying for Los Domos work is a spend fact;
- whether CI reimburses him is a later reporting/claim decision;
- `Facilities` is a CI reporting classification, not a property of the universal spend fact;
- Kirk entering a category subtotal in QuickBooks is a downstream accounting handoff, not the source spend.

## Existing Atlas seams reused

A live read-only schema inspection on 2026-09-10 confirmed these existing authorities:

- `atlas.organizations` — organization custody;
- `atlas.organization_units` — optional operating-unit scope;
- `atlas.organization_memberships` — internal human identity/relationship;
- `atlas.external_relationships` — known external payee/merchant relationship when one exists;
- `atlas.evidence_records` — generic evidence reference;
- `atlas.organization_ledger_entries` and `atlas.project_organization_ledger_event_internal_v1(...)` — organization-wide event projection.

The spend kernel must reuse those authorities rather than inventing duplicate people, merchants, receipts, organizations, or ledgers.

## Two canonical grains

### 1. Spend occurrence

`atlas.organization_spend_occurrences`

One occurrence represents one observed payment/charge/outlay event at its gross source amount.

Minimum facts:

- organization;
- optional organization unit where the occurrence is primarily situated;
- occurrence date and optional exact timestamp;
- gross amount and currency;
- funding kind: organization-funded, organization-member-funded, external-party-funded, or unresolved;
- payer membership when an organization member personally funded it;
- payee external relationship when known, plus a free-text payee label for fast capture;
- optional payment method/channel;
- source authority and source-system keys for replay/idempotency;
- recorder membership;
- truth state and provenance.

A spend occurrence amount is positive. Refunds/credits are not represented by negative spend values; they require a later credit/return money fact seam rather than overloading this primitive.

### 2. Spend allocation

`atlas.organization_spend_allocations`

One occurrence may support one or more purpose allocations.

This is necessary because one receipt or card charge can legitimately cover multiple purposes, projects, departments, activities, or later reporting categories.

An allocation preserves:

- its parent spend occurrence;
- allocated amount in the occurrence currency;
- optional organization-unit override;
- human-readable operational purpose;
- optional generic Atlas subject binding (`subject_domain`, `subject_kind`, `subject_id`) to work, project, event, asset, program, etc.;
- allocation state/provenance.

The allocation is **not** a CI expense category or GL account. Camps International can later classify the same allocation as `Facilities`; another downstream consumer can group it differently without changing the source allocation.

## Allocation invariant

At any effective position:

`sum(active allocation amounts) <= spend occurrence gross amount`

The unallocated remainder is explicit:

`gross amount - active allocations = unallocated amount`

An occurrence can therefore be captured immediately even if the human has not yet explained the whole purchase.

A downstream report that requires full allocation must raise an exception when an eligible spend still has an unallocated remainder.

If allocations are later replaced or split, Atlas should preserve prior allocation evidence through supersession rather than silently rewriting historical meaning. The exact transition/event implementation belongs to the canonical migration tranche; downstream consumers must eventually read one effective allocation position per the Atlas Effective Position Authority rule.

## Evidence

`atlas.organization_spend_evidence_links` links an occurrence, and optionally one specific allocation, to `atlas.evidence_records`.

Examples:

- receipt image;
- Mexican factura;
- emailed invoice;
- bank/card transaction observation;
- handwritten cash receipt;
- voice/manual note used to establish context.

Evidence is support for the spend fact; it does not itself become the spend amount unless admitted through the spend command.

The current live `evidence_records` read policy is person-self-only. That means organization-wide receipt visibility is **not yet solved** merely by adding this link. The eventual organization evidence/file custody membrane must explicitly govern who can view the actual supporting file.

## Payer semantics

`funding_kind` records whose resources initially funded the occurrence, not who may ultimately bear the accounting expense.

For example:

- `organization` — CI card/account directly paid;
- `organization_member` — David personally paid for CI/Los Domos purposes;
- `external_party` — another party funded it;
- `unresolved` — capture knows the spend but cannot yet establish funding source.

If `funding_kind = organization_member`, `payer_membership_id` is required and must belong to the same organization.

Reimbursement is deliberately separate. A member-funded spend may be reimbursable, non-reimbursable, donated, disputed, or split by policy. Reporting/claims decide that later.

## Payee semantics

Fast capture must not require merchant master-data work.

A spend can therefore have:

- `payee_external_relationship_id` when Atlas already knows the merchant/person; and/or
- `payee_label` from the receipt or human statement.

Identity reconciliation may later connect a label to an existing external relationship without invalidating the original observed text.

## Capture contract

The first narrow write seam should support an authenticated organization member saying, in effect:

> I spent 1,840 MXN at Home Depot for lumber at Los Domos.

The command should:

1. verify active organization membership;
2. verify any supplied organization unit belongs to that organization;
3. record one spend occurrence;
4. when a purpose is supplied, create one allocation for the full amount;
5. optionally link already-admitted evidence;
6. return stable IDs and the remaining unallocated amount;
7. avoid assigning CI reporting category, reimbursement status, QuickBooks account, exchange rate, or tax treatment.

AI/OCR/voice extraction may propose the command arguments, but database admission remains deterministic and idempotent.

## Organization Ledger projection

An accepted spend occurrence should eventually project to the existing Organization Ledger as a money-domain event so other Atlas surfaces can know that the spend happened.

The projection must not pretend a date-only observation has a more precise timestamp than the source provides. The exact date-only ledger occurrence convention must be established before the canonical migration wires automatic projection.

Until then, Spend remains canonical source truth and Reporting may bind directly to Spend allocations.

## Relationship to Organization Expense Reporting

The preferred expense-report source reference is a confirmed/effective `organization_spend_allocation`.

The report layer may then add:

- reporting eligibility;
- reimbursement treatment;
- CI category;
- Mexican factura requirement/state;
- exchange rate and reporting currency;
- export label/order;
- category subtotal/accounting handoff.

Thus:

`Spend occurrence -> Spend allocation -> CI expense line -> category subtotal -> Kirk accounting handoff`

No step is allowed to overwrite the step before it.

## Deliberately not included yet

- no universal income/revenue fact;
- no refund/credit fact;
- no double-entry accounting journal;
- no chart of accounts;
- no bank reconciliation;
- no reimbursement claim/payment lifecycle;
- no accounts payable lifecycle;
- no budget authority;
- no tax treatment;
- no automatic currency conversion;
- no QuickBooks API integration;
- no organization-wide file/evidence sharing policy;
- no production migration or deployment.

## First product proof

A synthetic fixture should prove:

1. David/member-funded MXN spend can be recorded without CI category knowledge;
2. a second spend in the same month can later receive the same CI reporting category;
3. each detail expense remains distinct;
4. the CI report can group both into one category subtotal;
5. the accounting handoff exposes only the subtotal while preserving both source allocations and evidence references;
6. a mixed-purpose receipt can be split into multiple spend allocations without inventing multiple gross payment events;
7. no QuickBooks or CI-specific field is required by the Spend kernel itself.

## Migration custody

This branch remains a schema proof. The canonical migration identity must be created through the governed `noel-core-db` production release process after the proof executes successfully under `BEGIN ... ROLLBACK` and after the branch is reconciled with current `main`.
