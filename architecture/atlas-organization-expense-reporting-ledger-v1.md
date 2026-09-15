# Atlas Organization Expense Reporting — Ledger-Custodied v1

## Status

Current-main Package 5 reporting candidate built from released Spend baseline:

`d3c7bf136c5225e1147b1fe051f0414a38b604a8`

Candidate migration identity:

`20260915235900_atlas_organization_expense_reporting_ledger_v1.sql`

This is source-only until Database Custody CI and protected production-schema clone validation pass. Production release remains a separate governed action.

## Source material and replay rule

Old PR #466 remains architectural source material, not executable history. Its durable distinctions are retained:

- report policy is interpretation over canonical Spend, never source financial truth;
- inclusion, category classification, and claim treatment are separate decisions;
- category meaning is distinct from an exact output/export label;
- currency conversion preserves explicit rate direction;
- month-end should surface deterministic unresolved questions rather than require blank-form reconstruction;
- detail lines remain traceable while category subtotals/accounting handoff are derived;
- AI suggestions may remain suggestions but do not silently become confirmed report truth.

Its September 11 SQL is stale because it predates Ledger custody, Principal root authority, and the released Spend schema. It is therefore replayed into one new post-tail migration rather than rebased or renamed.

## Governing flow

```text
canonical Spend occurrence
      ↓
active Spend allocation
      ↓
reporting admission
      ↓
report-specific inclusion / category / claim treatment
      ↓
rate + evidence requirements
      ↓
deterministic exceptions
      ↓
report detail lines
      ↓
category subtotals / accounting handoff
```

The reporting layer does not mutate Spend.

## Custody

Every reporting contract belongs to:

- one active `ledger_id`; and
- one Organization actively participating in that Ledger.

Periods, categories, rates, fact links, and audit events inherit and preserve the same Ledger + Organization pair.

A Spend allocation can enter a report only when both its allocation and parent Spend occurrence share that same Ledger + Organization custody.

An optional Organization Unit narrows a contract or period after Organization ownership is already established; it never substitutes for Ledger custody.

## Human authority

Authenticated setup, interpretation, readiness, reopening, and accounting-handoff reads require:

- current Principal; and
- active `root_governing` authority for the reporting Ledger.

Organization membership, when present, is recorded as institutional actor context. It is not treated as the root authorization primitive.

This tranche does not invent delegated employee expense-report authority. A later delegated consequence can widen the command membrane without changing reporting storage.

## Contract and categories

`organization_expense_reporting_contracts` stores organization-specific reporting policy/configuration, including:

- contract key and effective dates;
- reporting body/display identity;
- cadence;
- reporting currency;
- template configuration;
- accounting-handoff configuration;
- optional policy/template provenance references and hashes.

`organization_expense_reporting_categories` stores category meaning separately from exact export label.

A category may preserve:

- canonical label;
- export label;
- policy definition;
- examples;
- evidence rules;
- mapping state;
- sort order.

Atlas does not invent a mapping when source policy leaves it unresolved.

## Periods

A reporting period binds one active contract to one date range and the same Ledger + Organization custody.

States:

- `open`
- `review`
- `ready`
- `reopened`

Submission artifact provenance is deliberately deferred. `ready` means current blocking exceptions are zero; it does not claim an external submission occurred.

Only `open`, `review`, or `reopened` periods accept interpretation changes.

## Spend admission and interpretation

V1 admits only an active `organization_spend_allocations` row whose parent Spend occurrence is not voided.

One Spend allocation may be linked at most once under one reporting contract, and may not silently move between periods under that contract.

Three report decisions remain independent:

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
- `not_applicable`

Confirmed human decisions record current Principal and optional membership context.

## Rates

Rate direction is explicit. Currency rates preserve:

- source currency;
- reporting currency;
- quoted value;
- quote convention;
- canonical conversion multiplier;
- effective date window;
- source/provenance.

Canonical arithmetic is:

`report amount = source amount × conversion multiplier`

For `16.5 MXN per 1 USD`, quote convention is `source_units_per_one_reporting_unit`, therefore the canonical multiplier is `1 / 16.5` and `1,650 MXN = 100 USD`.

No label such as `MXN -> USD` is allowed to imply multiply-versus-divide.

## Exceptions are derived present-state questions

Atlas canon makes current state primary unless lineage is explicitly constitutive. Therefore this replay does **not** append generated exception rows indefinitely.

`organization_expense_reporting_exception_position_v1` derives current unresolved questions directly from current contract, period, Spend, interpretation, rates, categories, and Evidence.

V1 blocking questions:

- `reporting_eligibility_unresolved`
- `purpose_missing`
- `expense_category_unresolved`
- `reimbursement_treatment_unresolved`
- `exchange_rate_missing`
- `exchange_rate_ambiguous`
- `receipt_required_missing`

V1 warning:

- `template_field_state_missing`

When the underlying condition is corrected, the exception disappears from current state without requiring a synthetic resolution event.

Waiver authority is deferred until a real reporting policy establishes which requirements may legally or operationally be waived.

## Evidence

Reporting does not own receipts/facturas. It reads canonical Spend evidence links.

Category `evidence_rules` may state a report-specific requirement such as `requiresReceipt`. A missing required document becomes a derived reporting exception; the reporting layer does not manufacture Evidence.

## Detail projection and accounting handoff

Included Spend allocations become detail lines.

The detail projection preserves:

- source allocation and parent Spend ids;
- date/payee/purpose;
- source amount and currency;
- explicit applied rate;
- derived reporting amount;
- category meaning and export label;
- claim treatment;
- report-specific fields.

Primary final grouping/sort is category; detail lines remain visible.

Accounting handoff is a projection, not a second ledger. It provides category subtotals, report total, contributing fact/source ids, and configured destination metadata. No QuickBooks transaction is asserted until an actual downstream posting event is admitted later.

## Camps International pilot semantics retained from #466

The old reporting design documented these CI categories:

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

Observed exact export-label variants remain distinct from meaning, including:

- Goodwill -> `Goodwill/C/H`
- Honorarium -> `Honorariums`
- Hospitality/Lodging -> `Hospitality/Lodging/Meals`
- Program/Activity -> `Program/Act.`

`Printing` versus workbook `Publishing` remains unresolved. This replay does not invent that equivalence.

The old design's narrow receipt rule is preserved as configurable category policy: accommodation under Hospitality/Lodging can require a receipt. It does not become a universal receipt/factura requirement.

The CI contract/categories are **not seeded into production** by this generic migration. They belong to an explicit organization setup action after the kernel is released.

## Browser command membrane

Root-Ledger self APIs:

- `configure_organization_expense_reporting_contract_self_api_v1(...)`
- `open_organization_expense_reporting_period_self_api_v1(...)`
- `set_organization_expense_reporting_rate_self_api_v1(...)`
- `interpret_organization_spend_for_expense_report_self_api_v1(...)`
- `mark_organization_expense_reporting_period_ready_self_api_v1(...)`
- `reopen_organization_expense_reporting_period_self_api_v1(...)`
- `organization_expense_reporting_period_self_api_v1(...)`
- `organization_expense_reporting_accounting_handoff_self_api_v1(...)`

Direct authenticated/service table access is not an application contract.

## Release proof required

The production-shaped clone must prove:

1. contract custody requires active Ledger + Organization participation;
2. root-Ledger Principal authority is required for browser setup/review;
3. a CI-like MXN contract/rate converts 1,650 MXN to 100 USD under explicit quote direction;
4. category meaning/export label remain distinct;
5. an active Spend allocation cannot cross Ledger/Organization/period scope;
6. unresolved inclusion/category/claim/rate/evidence questions appear deterministically;
7. fixing their underlying current state makes those exceptions disappear;
8. receipt requirements read canonical Spend Evidence rather than duplicating it;
9. a ready period is impossible while blocking exceptions remain;
10. category detail/subtotals and report total reconcile deterministically;
11. source interpretation events are append-only audit history;
12. direct table/view mutation is closed to browser/service roles;
13. released Spend, Commercial Financial Reality, and Package-4 Flower v2 remain intact;
14. production migration itself seeds no business reporting contract, period, rate, or fact rows.
