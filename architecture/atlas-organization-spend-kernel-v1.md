# Atlas Organization Spend Kernel v1

**Status:** Current-main candidate architecture  
**Scope:** Canonical organization-owned spend occurrence, purpose allocation, audit, and evidence binding  
**Pilot:** Camps International / Los Domos expense reporting  
**Database authority:** `noel-core-db`

## Purpose

Atlas needs one universal organization money fact beneath reimbursement forms, expense reports, project costing, budgets, and accounting handoffs.

The kernel answers:

> What value was actually spent for organization purposes, by whom, to whom, when, in what currency, and what was it for?

It does **not** decide how an organization later classifies, reimburses, books, taxes, budgets, or reports the spend.

The governing sequence is:

`source/evidence -> Spend occurrence -> purpose allocation -> organization-specific reporting/accounting interpretation`

For Camps International, `Facilities` is therefore not a Spend field. It is a later CI reporting interpretation of a Spend allocation.

## Current-main boundary check

Read-only production inspection on 2026-09-10 confirmed:

- `atlas.commercial_payments` already exists, but it represents universal observed **commercial/customer payment** identity and amount, with provider lifecycle events. Organization outlays must not be folded into that inbound/commercial payment authority.
- `atlas.organizations` is the organization custody root.
- `atlas.organization_units` supports organization-scoped operating units.
- `atlas.organization_memberships` is the internal human relationship authority.
- `atlas.external_relationships` is the existing external merchant/payee relationship authority when the payee is already known.
- `atlas.evidence_records` is the generic evidence primitive.
- `atlas.current_organization_membership_v1(...)` and `atlas.is_organization_owner(...)` are current identity/authorization seams.
- `atlas.organization_ledger_entries` is a projection authority, not the source table for Spend.

Spend therefore remains a separate canonical operational-money kernel.

## Canonical grains

### Spend occurrence

`atlas.organization_spend_occurrences`

One row is one observed gross payment/charge/outlay event.

It preserves:

- organization and optional organization unit;
- date and optional exact timestamp;
- gross amount and currency;
- initial funding source kind;
- member payer when a member personally funded the spend;
- known external payee relationship when available plus the observed/free-text payee label;
- optional payment method/channel;
- stable source kind/key for idempotency;
- recording membership;
- current truth state;
- provenance and metadata.

A Spend amount is positive. Refunds/credits are not encoded as negative spending; a later return/credit money fact can correlate to the original Spend without changing its historical meaning.

### Spend allocation

`atlas.organization_spend_allocations`

One occurrence can have zero, one, or many active purpose allocations.

An allocation preserves:

- parent Spend occurrence;
- allocated amount in the occurrence currency;
- optional organization-unit override;
- operational purpose;
- optional generic Atlas subject binding (`subject_domain`, `subject_kind`, `subject_id`);
- recording membership;
- lifecycle state.

The allocation is still operational truth. It is **not** a CI category, GL account, tax code, reimbursement decision, or QuickBooks line.

A 1,500 MXN receipt can therefore remain one Spend occurrence while being allocated as 1,000 MXN building maintenance and 500 MXN program supplies.

## Allocation invariant

For each non-voided occurrence:

`sum(active allocations) <= gross amount`

and:

`unallocated amount = gross amount - sum(active allocations)`

Capture is allowed before purpose is known. Reporting contracts that require complete allocation may block close while `unallocated amount > 0`.

Replacing a split never deletes prior allocation rows. Existing active allocations are superseded and replacement allocations become the effective position.

## Audit and correction

Spend is financial history, so a correction cannot be a silent row rewrite.

`atlas.organization_spend_events` records every governed mutation to the current Spend position with:

- event kind;
- actor membership;
- source kind/key;
- timestamp;
- reason;
- before-state snapshot;
- after-state snapshot;
- metadata.

The typed occurrence row remains the current position for efficient consumers; the append-only event history preserves how that position was established or changed.

Initial v1 event kinds are intentionally narrow:

- `recorded`
- `corrected`
- `allocations_replaced`
- `voided`

Refunds and money returned are not `corrected` or `voided`; they are distinct later money facts.

## Funding semantics

`funding_kind` records whose resources initially funded the occurrence:

- `organization`
- `organization_member`
- `external_party`
- `unresolved`

For `organization_member`, `payer_membership_id` is required and must belong to the same organization.

This is deliberately separate from reimbursement treatment. David can personally fund a Los Domos purchase before Atlas or CI decides whether it is reimbursable, donated/non-reimbursed, disputed, or treated another way.

## Payee semantics

Fast capture must not require merchant master-data work.

A Spend occurrence can therefore preserve both:

- `payee_external_relationship_id` when Atlas already knows the external party; and
- `payee_label`, such as the literal merchant name read from a receipt.

Later identity reconciliation can bind an observed label to an existing relationship without erasing the original observation.

## Evidence

`atlas.organization_spend_evidence_links` binds organization-scoped `atlas.evidence_records` to a Spend occurrence and, optionally, one specific allocation.

Examples include receipt, factura, invoice, bank/card observation, and contextual evidence.

Evidence supports the Spend fact; it does not itself become money truth merely because OCR/model extraction produced an amount.

## Write membrane

Direct application writes to Spend tables are not allowed.

The first governed membrane consists of:

- an internal record command that validates organization custody and source idempotency;
- `record_organization_spend_self_api_v1(...)` for an authenticated organization member recording a spend;
- `replace_organization_spend_allocations_self_api_v1(...)` for a governed purpose split/reallocation;
- `correct_organization_spend_self_api_v1(...)` for audited correction of the current typed position;
- `void_organization_spend_self_api_v1(...)` for a governed declaration that the occurrence should no longer participate as active Spend truth;
- stable read projections through self APIs rather than table grants.

A normal member may record their own member-funded Spend. Recording another member as the initial payer or altering another member's record requires elevated organization authority in the v1 membrane.

AI/OCR/voice extraction can propose command arguments, but model output does not bypass these commands.

## Source identity

Current-main Atlas commonly uses `source_kind` + `source_key` for stable observed identity. Spend v1 follows that convention.

`(organization_id, source_kind, source_key)` is unique.

For manual/UI capture the application supplies a stable client event key. For future provider/import capture, the provider/import adapter supplies a durable source key. Exact retry returns the existing Spend; conflicting retry under the same source identity is rejected.

## Read position

`atlas.organization_spend_position_v1` exposes:

- typed occurrence position;
- allocated amount;
- unallocated amount;
- active allocation count.

A self API returns organization-member-safe Spend data without granting direct table reads.

## Organization Ledger

Spend is source truth; Organization Ledger is a projection.

The current Organization Ledger projection function requires an exact `timestamptz`, while Spend must permit date-only observations. V1 therefore does **not** fabricate a midnight occurrence time merely to project the row. Ledger projection can be added after a governed date-only occurrence convention exists.

## Relationship to CI reporting

The preferred CI expense-report source is an effective `organization_spend_allocation` plus its parent occurrence.

The reporting contract may then add:

- inclusion/eligibility;
- reimbursement treatment;
- CI category;
- receipt/factura requirements;
- exchange rate and USD report amount;
- export label/order;
- category subtotal and downstream accounting handoff.

Thus:

`Spend occurrence -> Spend allocation -> CI expense interpretation -> category subtotal -> QuickBooks handoff`

No downstream interpretation overwrites Spend.

## Deliberately not included in Spend v1

- income/revenue;
- refund/credit fact;
- double-entry accounting journal;
- chart of accounts;
- bank reconciliation;
- reimbursement payment lifecycle;
- accounts payable;
- tax treatment;
- automatic currency conversion;
- QuickBooks integration;
- report-specific expense categories;
- production deployment.

## Release test

The current-main candidate must prove:

1. member-funded MXN spend records without CI knowledge;
2. exact source retry is idempotent and conflicting retry is rejected;
3. payer/member, unit, merchant relationship, and evidence cannot cross organization custody;
4. one gross receipt can support multiple purpose allocations;
5. active allocations cannot exceed gross amount;
6. replacing allocations preserves old rows as superseded history;
7. corrections and voids produce append-only audit events;
8. direct authenticated table writes/reads are unavailable;
9. self API reads return the effective current position;
10. CI reporting can bind to Spend allocation IDs without introducing CI fields into this kernel.

## Migration custody

This document is materialized from current `main` on `feature/atlas-organization-expense-reporting-v1-main-sync`. The corresponding migration may be committed and validated on the branch, but applying it to the production project remains a separate release action requiring explicit approval.
