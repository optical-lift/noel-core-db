# Atlas Organization Expense Reporting v1

**Status:** Stacked current-main candidate architecture  
**Scope:** Organization-owned reporting contracts, classifications, report periods, rates, exceptions, and accounting handoff  
**Pilot:** Camps International / Mexico monthly reporting  
**Depends on:** Atlas Organization Spend Kernel v1 (`20260911012500`)  
**Database authority:** `noel-core-db`

## Purpose

This layer translates canonical organization facts into a particular organization's required expense-reporting form without turning that form into source truth.

The governing flow is:

`Spend occurrence -> Spend allocation -> reporting admission -> organization classification -> report conversion -> exception review -> detail report -> category subtotal -> accounting handoff`

The reporting layer never changes the underlying Spend occurrence or allocation.

## Universal boundary

The module is organization-owned. An optional `organization_unit_id` narrows a contract or period to a real operating unit when organization structure warrants it.

It owns:

- reporting contract identity/version/configuration;
- organization-specific categories and policy meanings;
- exact output labels separately from category meaning;
- reporting periods;
- accepted reporting rates;
- links to canonical source facts;
- report-specific inclusion/classification/claim treatment;
- unresolved close exceptions;
- deterministic report and accounting-handoff projections;
- eventual submitted-artifact provenance.

It does not own:

- the payment itself;
- operational purpose of the Spend allocation;
- receipts/facturas as evidence;
- travel/mileage truth;
- participant/impact truth;
- chart of accounts;
- downstream QuickBooks transactions.

## Source fact contract

For expense lines, v1 admits only an effective active `atlas.organization_spend_allocations` row whose parent `atlas.organization_spend_occurrences` row is not voided.

The report link preserves the canonical source identity as:

- `source_kind = organization_spend_allocation`
- `source_id = <allocation uuid>`

One allocation can be admitted at most once under one reporting contract. A contract must not silently place the same source allocation into two periods.

## Reporting interpretation states

Three decisions remain separate:

### Inclusion

- `unresolved`
- `suggested`
- `included`
- `excluded`

### Category classification

- `unclassified`
- `suggested`
- `confirmed`
- `not_applicable`

### Claim treatment

- `unresolved`
- `reimbursement`
- `organization_paid`
- `documentation_only`
- `donated_non_reimbursed`

An AI/model suggestion may populate suggested state and confidence. It may not silently become `included`, `confirmed`, or an authoritative reimbursement claim.

## Category meaning vs output label

Category meaning and export label are separate authority.

The supplied Camps International policy categories are:

- Connection/IT
- Entertainment
- Equipment/Tools
- Facilities
- Fees
- Goodwill
- Honorarium
- Hospitality/Lodging
- Office/Library
- Other
- Per Diem/Meals
- Printing
- Program/Activity
- Record of Transaction
- Travel

Observed workbook label variants include:

- Goodwill -> `Goodwill/C/H`
- Honorarium -> `Honorariums`
- Hospitality/Lodging -> `Hospitality/Lodging/Meals`
- Program/Activity -> `Program/Act.`

`Printing` versus workbook `Publishing` remains explicitly unresolved until Camps International establishes the intended mapping. Atlas must not manufacture that equivalence.

## Reporting periods

A reporting period binds one contract/version to a closed date window.

Suggested states:

- `open`
- `review`
- `ready`
- `submitted`
- `reopened`
- `closed`

Only open/review/reopened periods accept new interpretations. `ready` means no open blocking exception remains. `submitted` requires artifact/submission provenance in a later tranche.

## Rate semantics

Rate direction must be explicit.

Each currency rate preserves:

- source currency;
- reporting currency;
- original quoted value;
- quote convention;
- canonical conversion multiplier;
- effective date window;
- source/provenance;
- confirmation state and confirming membership when required.

Canonical arithmetic is always:

`report amount = source amount * conversion multiplier`

For the observed CI Mexico workbook quote of `16.5 MXN per 1 USD`:

- quoted value = `16.5`
- convention = `source_units_per_one_reporting_unit`
- canonical MXN->USD multiplier = `1 / 16.5`

Therefore `1,650 MXN -> 100 USD`.

Atlas must never infer multiply-versus-divide from a label such as `MXN -> USD`.

## Exception model

Month-end is exception review rather than blank-form reconstruction.

Blocking expense exceptions in v1:

- `reporting_eligibility_unresolved`
- `purpose_missing`
- `expense_category_unresolved`
- `reimbursement_treatment_unresolved`
- `exchange_rate_missing`
- `exchange_rate_ambiguous`
- `receipt_required_missing`
- `category_subtotal_reconciliation_failed`

CI pilot warning/configuration state:

- `mexican_factura_state_missing`

Exceptions are deterministic current-state questions. Rebuilding exceptions must not append duplicate unresolved questions forever; stale generated exceptions should resolve/disappear when their cause is no longer present.

## Receipt rule supported by CI source

The supplied Camps International category policy establishes one narrow mandatory evidence rule used by this v1 design: accommodation expenses under Hospitality/Lodging require a receipt.

The supplied material does not establish a universal rule that every CI category requires a receipt or Mexican factura. The workbook's factura field is therefore reportable configuration/state, not an invented universal rejection rule.

## Final CI Expense projection

Each included, confirmed expense remains one detail line backed by one Spend allocation.

The CI Expense presentation contract is:

- **primary/final grouping and sort: expense category**;
- preserve individual detail lines;
- date and amount remain line attributes, not the primary sort authority;
- stable secondary order may be configured independently;
- show one subtotal for each category;
- category subtotal must equal the sum of its contributing detail-line USD amounts;
- report total must equal the sum of category subtotals.

A reconciliation mismatch is blocking; rendering cannot silently repair it.

## Accounting handoff

The accounting handoff is a projection, not a second ledger.

For the current Camps International workflow:

- destination adapter: QuickBooks;
- responsible role: treasurer;
- current operator instance: Kirk;
- posting grain: one USD subtotal per expense category;
- detailed expense report remains intact;
- detailed report is uploaded downstream as documentary proof/support.

Atlas should expose both:

- grouped detailed report lines; and
- `accountingSummary` containing one reconciled amount per category plus contributing source IDs.

QuickBooks-specific transaction identifiers or attachment results become canonical only if/when Atlas actually performs or records downstream posting.

## Stable database objects

The eventual canonical migration should establish:

- `atlas.organization_expense_reporting_contracts`
- `atlas.organization_expense_reporting_categories`
- `atlas.organization_expense_reporting_periods`
- `atlas.organization_expense_reporting_rates`
- `atlas.organization_expense_reporting_fact_links`
- `atlas.organization_expense_reporting_exceptions`

and governed RPC/projection seams for:

- contract/period retrieval;
- source Spend admission;
- classification confirmation;
- exception resolution/waiver;
- close-readiness evaluation;
- deterministic detail-line projection;
- category/accounting subtotal projection.

Direct authenticated table writes should not be the application contract.

## Camps International pilot fields

### Expense output

- sequence
- date from/on
- date to
- purpose/description
- expense type export label
- Mexican factura indicator
- MXN amount
- adjusted exchange rate
- USD amount

### Travel output

The same reporting-contract framework can later project date/range, origin, destination, purpose, vehicle/distance basis, odometer/distance, reimbursement rate, and USD amount from a future canonical travel/mileage authority.

### Impact output

The same framework can later project event, participant age bands, total, and VOICE/Other from canonical activity/participant truth.

Travel and Impact are deliberately not invented inside the Expense/Spend kernel.

## Release ordering

This is a stacked design over unreleased Spend v1. The reporting migration must not be submitted to production-schema clone validation until the Spend migration is either:

1. present in the disposable clone's canonical production baseline because it has been released; or
2. the governed validator gains an explicit multi-migration candidate-package authority.

Until then, reporting SQL may be developed as reviewed architecture/proof material but must not masquerade as independently clone-validatable production DDL.

## Governing acceptance test

The pilot is working when David can accumulate real spending throughout the month and Atlas can produce, without reconstructing the month from scratch:

1. distinct source-backed expense detail lines;
2. only the unresolved questions that genuinely require human judgment;
3. correct MXN-to-USD conversion under the accepted CI rate;
4. final grouping by CI category;
5. deterministic category subtotals;
6. one accounting-handoff amount per category for the treasurer;
7. full traceability from subtotal -> detail line -> Spend allocation -> Spend occurrence -> evidence;
8. the intact detail report as downstream documentary proof.
