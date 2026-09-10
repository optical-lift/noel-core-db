# Atlas Organization Spend -> Expense Reporting Bridge v1

**Status:** Candidate integration contract  
**Upstream authority:** Atlas Organization Spend Kernel v1  
**Downstream consumer:** Atlas Organization Expense Reporting v1

## Purpose

Define the exact seam between universal spend truth and an organization's expense-report interpretation without creating a hard deployment dependency between the two current schema proofs.

## Source authority

Once the Organization Spend Kernel is canonically released, an ordinary expense-report detail line should bind to:

- `source_authority = atlas.organization_spend_allocations`
- `source_ref = <organization_spend_allocation.id>`

The reporting layer must resolve the allocation through its parent occurrence and verify all of the following before admission:

1. allocation and report belong to the same organization;
2. allocation is in the effective active position;
3. occurrence is not voided/disputed in a way the reporting contract disallows;
4. allocation amount is positive and within the source occurrence's canonical allocation position;
5. occurrence date falls within the reporting period or an explicit organization policy permits another treatment;
6. organization-unit scope is compatible with the reporting contract/period;
7. the same allocation is not admitted twice to the same reporting contract/period unless the contract explicitly supports split reporting treatment.

## Fields derived from Spend

Expense reporting should derive, not duplicate as independent truth:

- source date from `organization_spend_occurrences.occurred_on`;
- source currency from the occurrence;
- source amount from the allocation;
- payer/member relationship from the occurrence;
- payee label/relationship from the occurrence;
- operational purpose from the allocation when present;
- receipt/factura and transaction evidence through Spend evidence links.

The reporting layer may preserve a report-specific purpose/description when the organization's form requires wording different from the operational purpose, but it must retain the source purpose/provenance.

## Fields owned by Reporting

The following remain downstream interpretation and must never be written back into Spend truth:

- report eligibility;
- reimbursement treatment;
- reporting category;
- category export label;
- factura-required/reporting state;
- exchange rate used by that report;
- converted/reporting-currency amount;
- presentation ordering;
- category subtotal;
- QuickBooks/accounting handoff metadata.

## Multi-purpose receipt behavior

If one gross spend occurrence has two active allocations, each allocation is independently reportable.

Example:

`Walmart 1,500 MXN`

- allocation A: `1,000 MXN — cleaning/maintenance supplies`
- allocation B: `500 MXN — participant activity supplies`

CI may classify A as `Facilities` and B as `Program/Activity`. Atlas must not manufacture two 1,500 MXN payments or lose the single receipt relationship.

## Reporting amount

For the CI pilot, each expense detail line has both:

- `sourceAmountMXN` — canonical Spend allocation amount;
- `amountUSD` — report projection calculated under the accepted CI exchange-rate rule.

The USD amount is not canonical Spend truth. It belongs to the report-period projection because the applicable conversion rule/rate is organization- and period-specific.

## Accounting handoff

The QuickBooks subtotal is derived only after report classification and conversion:

`active spend allocations -> CI expense lines -> CI category -> report USD line amounts -> category USD subtotal -> accounting handoff`

Kirk's category subtotal must therefore reconcile to the detail lines in **reporting currency**, while the underlying Spend kernel still preserves the source-currency amount.

## Transitional behavior

Until Organization Spend is released, `organization_expense_reporting_fact_links` may continue to carry evidence/manual transitional sources. Those links must remain distinguishable from canonical Spend-backed lines.

After Spend release, ordinary captured purchases/payments should prefer the Spend allocation authority rather than adding new evidence-only expense rows.

## Acceptance fixture

Using the synthetic CI fixtures:

- Home Depot lumber: 1,840 MXN -> Facilities
- plumbing fittings: 920 MXN -> Facilities
- mixed Walmart receipt: 1,000 MXN allocation -> Facilities; 500 MXN allocation -> Program/Activity

Expected source-currency grouping before conversion:

- Facilities: 3,760 MXN
- Program/Activity: 500 MXN

Every subtotal must retain the exact included allocation IDs, so a reviewer can traverse from Kirk's summarized accounting number back through CI report detail to the original Spend occurrence and supporting evidence.
