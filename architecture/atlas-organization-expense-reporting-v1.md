# Atlas Organization Expense Reporting v1

**Status:** Candidate architecture  
**Scope:** Organization-owned expense/travel/impact reporting contract and monthly close  
**Pilot:** Camps International / Mexico reporting used by David Caldwell  
**Database authority:** `noel-core-db`

## 1. Purpose

Atlas Organization Expense Reporting translates real operational and financial facts into an organization's required reimbursement/reporting format without making the human reconstruct the month afterward.

The governing flow is:

`real-world activity -> evidence -> domain-owned fact -> organization reporting interpretation -> exception review -> finished report -> accounting handoff`

The reporting layer does not become the source of the expense, trip, or activity. It stores the organization's rules for interpreting known reality and compiling it into the required artifact.

## 2. Existing Atlas seams confirmed September 10, 2026

A read-only inspection of the live shared `atlas` schema confirmed that Atlas already has the custody seams this feature should use:

- `atlas.organizations` — canonical organization identity;
- `atlas.organization_units` — subdivisions/operating units under an organization;
- `atlas.organization_ledger_entries` — organization-level truth projection with provenance/correlation;
- `atlas.evidence_records` — generic evidence primitive;
- `atlas.organization_memberships` — human relationship to an organization;
- `atlas.operational_routes` / `atlas.operational_route_events` — existing route/event truth where applicable;
- `atlas.community_events` — existing event truth for the community-event domain.

Therefore the reporting contract is **organization-owned**, not Principal-owned. `principal_id` is not the custody root for this feature.

An optional `organization_unit_id` allows a contract or report period to be scoped to an operating unit such as a site/program when that is the organization's actual structure. This is how Los Domos can be represented if it is an operating unit of Camps International; Atlas should not decide that legal/accounting relationship by inference.

`atlas.evidence_records` can provide evidence references, but it is not automatically an expense ledger. The live schema inspection did not establish a released universal canonical expense/payment or travel/mileage fact table, so this module must not invent one silently.

## 3. Pilot problem

The supplied Camps International Mexico workbook has three output sheets:

1. **Expense** — date/range, purpose, expense type, Mexican factura state, MXN amount, adjusted exchange rate, USD amount.
2. **Travel** — date/range, origin, destination, purpose, vehicle/odometer or distance, reimbursement rate, USD amount.
3. **Impact** — event, participant counts in age bands 0–8, 9–16, 17+, total, and VOICE/Other classification.

These are three projections over overlapping monthly reality, not three independent capture workflows. One real activity may legitimately feed Expense, Travel, and Impact at the same time.

A further Camps International accounting requirement was clarified September 10, 2026: expense categories may repeat throughout the month, but the final expense presentation should be grouped/sorted by **category**, with a subtotal for each category. The treasurer should then be able to enter the one category subtotal into QuickBooks while retaining/uploading the detailed report as documentary proof. This accounting handoff is a projection over the report, not a second expense ledger.

## 4. Governing rules

### 4.1 Domain truth remains domain-owned

Organization Expense Reporting does not create a second canonical ledger of money, travel, or program truth.

- payment/expense truth belongs to the owning money/transaction domain;
- trip/mileage truth belongs to the owning travel/mobility domain;
- event/participant truth belongs to the owning activity/program domain;
- receipts/facturas are evidence and remain under evidence/file custody.

The reporting module owns only:

- reporting contracts and versions;
- organization-specific categories and meanings;
- report periods;
- accepted rates;
- links to source facts/evidence;
- organization-specific classifications/interpretations;
- close exceptions;
- export/submission provenance.

Where no released source-domain fact exists yet, the system may link transitional evidence/manual capture, but transitional capture must remain visibly transitional and must not become permanent authority merely because it can populate a report.

### 4.2 Meaning is separate from export label

An organization category has two separate concerns:

- **canonical meaning** — what the organization's policy says the category means;
- **export label** — the exact shorthand expected by a specific template.

The CI pilot proves this is necessary. The policy uses labels including `Goodwill`, `Honorarium`, `Hospitality/Lodging`, `Printing`, and `Program/Activity`; the workbook contains shorthand/alternate labels including `Goodwill/C/H`, `Honorariums`, `Hospitality/Lodging/Meals`, `Publishing`, and `Program/Act.`.

Atlas must not treat label differences as semantic truth or silently map `Publishing` to `Printing` without CI authority.

### 4.3 Capture once, report many

A source fact or evidence item can be linked once to the reporting period and interpreted into the required projection(s). One underlying activity may therefore contribute an expense line, a travel line, an impact line, or any valid combination.

### 4.4 Month-end is exception handling

A close begins with what Atlas already knows, not a blank form. Atlas compiles eligible facts and creates explicit exceptions only for unresolved required information, such as:

- missing receipt/factura;
- missing purpose;
- unresolved category;
- reimbursement eligibility needing judgment;
- missing/unsupported exchange rate;
- missing travel origin/destination/distance basis;
- missing impact age breakdown;
- missing VOICE/Other classification.

A report period is `ready` only when blocking exceptions are resolved or explicitly waived by authorized organization judgment.

### 4.5 The report file is a projection

The submitted spreadsheet/PDF/file is not the canonical fact store. Atlas must preserve provenance from every output row back to the source fact/evidence, governing contract version, classification, applied rate, human resolution/waiver, and final submitted artifact.

### 4.6 Final presentation sort is contract-owned

The report's output ordering is a presentation rule, not a change to fact chronology.

For the Camps International Expense projection, the final/primary sort is **expense category**, not date and not amount. Date and amount remain attributes of each detail line. The contract may define a stable secondary order within a category.

This sort requirement must be configurable because another organization may require chronological, project, account-code, funding-source, department, or other ordering.

### 4.7 Category subtotals are accounting reconciliation units

Repeated detail lines within the same reporting category must remain individually preserved, while the report may additionally expose a deterministic subtotal for that category.

For every category group:

`sum(detail line report amounts) = category subtotal`

and across the full report:

`sum(category subtotals) = report expense total`

A mismatch is a blocking close exception. Atlas must never repair a discrepancy silently in rendering.

### 4.8 Accounting handoff is downstream and software-neutral

A reporting contract may define an accounting handoff projection that translates accepted report detail into the grain required by a downstream accounting workflow.

For Camps International, the current destination is QuickBooks and the posting grain is **one amount per expense category subtotal**. The full detailed report remains documentary proof/supporting documentation.

QuickBooks is an adapter/destination, not a canonical Atlas concept. The same handoff model must be usable with another accounting system or a manual bookkeeper workflow.

Named people are instances, not schema. Kirk is the current CI treasurer/operator for this handoff; the reusable structure should point to the responsible organization role/membership when persisted.

## 5. Core objects

### `organization_expense_reporting_contracts`

Organization-owned effective-dated reporting rules. Holds `organization_id`, optional `organization_unit_id`, stable contract key, reporting-body label, cadence, currency expectations, policy/template provenance, configuration, and lifecycle state.

### `organization_expense_reporting_categories`

Organization-specific category definitions under a contract version: stable key, canonical label, export label, policy definition, examples/notes, sort order, active state.

### `organization_expense_reporting_periods`

One reporting window under one contract: organization/unit scope, period start/end, reporting identity, close state, and submitted-artifact provenance.

### `organization_expense_reporting_rates`

Accepted exchange/mileage/distance rates for a report period or narrower effective window, including source/provenance and human confirmation when applicable.

### `organization_expense_reporting_fact_links`

Binds a source fact/evidence item to a reporting period without taking ownership of that source. Supports:

- `fact_kind`: `expense`, `travel`, `impact_activity`;
- `source_authority` and immutable `source_ref`;
- optional direct `evidence_record_id` when the source is `atlas.evidence_records`;
- optional expense category;
- classification state/confidence;
- report-specific purpose/description;
- export-only shaping metadata.

### `organization_expense_reporting_exceptions`

First-class unresolved requirements: period, optional fact link, exception code, blocking/warning severity, human-readable question, state, resolution/waiver, resolver, timestamp.

### Accounting handoff projection

The initial implementation should remain a stable projection over accepted report state rather than a new canonical accounting table. It should expose:

- grouped detail lines;
- category/accounting subtotals;
- overall reconciliation state;
- downstream destination metadata;
- documentary-artifact relationship.

A first-class downstream posting event should be introduced only when Atlas must persist facts such as an actual QuickBooks transaction identifier, attachment upload, posting result, reversal, or reconciliation event.

## 6. Camps International pilot category contract

Preserve the supplied policy meanings for:

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

Template labels remain separately configured. `Publishing` remains unresolved until Camps International establishes its intended relationship to `Printing`.

## 7. CI pilot output contract

### Expense

Sequence, date from/on, date to, purpose/description, expense-type export label, Mexican factura indicator, MXN amount, adjusted rate, USD amount.

Presentation/accounting rules:

- primary final sort: category;
- group by category;
- retain all detail lines;
- show subtotal for each category;
- category subtotal is the accounting handoff amount;
- retain/generate the complete detail report as documentary proof for downstream accounting.

### Travel

Date from/to, origin, destination, purpose/description, vehicle/distance basis, odometer start/stop where applicable, total miles/km, reimbursement rate, USD amount.

### Impact

Event, age 0–8, age 9–16, age 17+, total participants, VOICE/Other.

## 8. Application contract

Atlas application repositories should consume released database RPC/projection seams rather than making direct-table writes the product architecture.

The database authority should eventually release seams for:

1. active contract/category retrieval;
2. report-period bundle retrieval;
3. admission/linkage of an authorized source fact/evidence item;
4. classification confirmation;
5. exception resolution/waiver;
6. deterministic close-readiness evaluation;
7. stable export payload generation;
8. accounting handoff projection with deterministic category/group subtotals;
9. submission/documentary-artifact provenance recording.

AI may extract or suggest classifications, but suggestions are not authoritative until accepted under organization rules.

## 9. First implementation tranche

This v1 tranche may establish the reporting interpretation boundary only:

- contracts;
- categories;
- periods;
- rates;
- source-fact/evidence links;
- exceptions;
- read/projection contract;
- configurable output grouping/sorting/subtotals/accounting-handoff metadata.

It must not invent permanent canonical expense, travel, participant, receipt, organization, operating-unit, or downstream-accounting truth merely to finish David's report.

## 10. Next seams to resolve

1. Decide whether Los Domos is an `organization_unit` of Camps International or requires a separate organization/reporting contract based on actual accounting authority.
2. Design/release the canonical money/expense fact seam needed for reimbursement expenses.
3. Design/release the canonical travel/mileage fact seam.
4. Reuse existing event truth where valid and determine a universal participant/impact fact seam where it is not.
5. Define receipt/factura evidence values and durable file locator/hash conventions using `atlas.evidence_records` plus file custody.
6. Reconcile CI workbook-only `Publishing` and combined shorthand labels with CI policy authority.
7. Establish authoritative exchange/mileage rate source and approval rules.
8. Confirm CI's downstream QuickBooks posting convention: exact transaction form, posting date, account/code mapping, and whether category subtotals are entered as lines of one transaction or separate transactions.
9. Build the exact workbook renderer only after the stable export and accounting-handoff payloads exist.

## 11. Governing test

The feature is working when David can live the month normally, capture evidence close to the moment it occurs, and reach month-end with Atlas asking only for information it could not already know — while Camps International receives the exact report it requires, every output row remains traceable to real evidence and an authorized organization reporting rule, repeated category lines reconcile to correct category subtotals, and the treasurer can use those subtotals for downstream accounting without losing the detailed documentary record.
