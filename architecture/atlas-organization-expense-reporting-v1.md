# Atlas Organization Expense Reporting v1

**Status:** Candidate architecture  
**Scope:** Organization-owned expense/travel/impact reporting contract and monthly close  
**Pilot:** Camps International / Mexico reporting used by David Caldwell  
**Database authority:** `noel-core-db`  

## 1. Purpose

Atlas Organization Expense Reporting translates real operational and financial facts into an organization's required reimbursement/reporting format without making the human reconstruct the month after the fact.

The governing flow is:

`real-world activity -> source evidence -> domain-owned fact -> organization reporting interpretation -> exception review -> finished report`

The reporting layer does not become the source of the expense, trip, or activity. It preserves the organization's rules for interpreting already-known reality and compiling that reality into a required reporting artifact.

## 2. Pilot problem

The Camps International Mexico workbook supplied for the pilot has three output sheets:

1. **Expense** — expense date/range, purpose, expense type, Mexican factura state, MXN amount, adjusted exchange rate, USD amount.
2. **Travel** — date/range, origin, destination, purpose, vehicle/odometer or distance, reimbursement rate, USD amount.
3. **Impact** — event, participant counts in age bands 0–8, 9–16, 17+, total, and VOICE/Other classification.

These are three reporting projections over overlapping monthly reality, not three independent capture workflows.

A single activity may legitimately produce all three projections. Example: a pastors breakfast in Morelia may contain an expense, travel, and impact counts. Atlas should capture/link that reality once and compile every required reporting projection from it.

## 3. Governing rules

### 3.1 Domain truth remains domain-owned

Organization Expense Reporting does not create a second ledger of canonical financial or operational truth.

- expense/payment truth belongs to the owning Atlas money/transaction domain;
- trip/mileage truth belongs to the owning travel/mobility domain;
- event/participant truth belongs to the owning activity/program domain;
- receipt/factura files remain source evidence under their owning custody mechanism.

This module stores organization reporting rules, reporting-period state, interpretations/classifications, source-fact references, and close exceptions.

Until a released canonical domain fact exists, a reporting link may identify evidence-only/manual capture as a transitional source. Transitional capture must not be promoted into permanent domain authority merely because it allows an export to succeed.

### 3.2 Meaning is separate from export label

An organization's category has at least two independent representations:

- **canonical meaning** — what the organization says the category means;
- **export label** — the exact shorthand/text expected in a particular template.

The Camps International pilot proves this distinction is necessary. The policy language includes categories such as `Goodwill`, `Honorarium`, `Hospitality/Lodging`, and `Program/Activity`, while the supplied workbook uses shorthand or combined labels such as `Goodwill/C/H`, `Honorariums`, `Hospitality/Lodging/Meals`, and `Program/Act.`.

Atlas must never infer that a different label necessarily means a different accounting meaning.

### 3.3 Capture once, report many

A reporting fact link points back to the source fact. It may then carry the organization-specific interpretation required by the contract.

One source activity can therefore participate in:

- one or more expense lines;
- one or more travel lines;
- one impact line;
- or no line for a given contract.

### 3.4 Month-end is exception handling

The monthly close should not begin by presenting a blank form.

Atlas should compile all eligible source facts for the reporting period, apply known reporting rules, and produce a finite exception queue for unresolved requirements such as:

- missing receipt/factura evidence;
- missing purpose;
- unresolved expense category;
- uncertain reimbursement eligibility;
- missing exchange rate;
- missing travel origin/destination;
- missing vehicle/distance/odometer information;
- missing impact age breakdown;
- missing VOICE/Other classification.

A period becomes `ready` only when blocking exceptions are resolved or explicitly waived by authorized human judgment.

### 3.5 Reporting artifact is a projection

The submitted spreadsheet/PDF/file is an artifact generated from the period's accepted facts and reporting interpretations. It is not the canonical store of those facts.

Atlas must preserve enough provenance to answer:

- what source fact produced each output row;
- which contract/version governed the interpretation;
- which category meaning and export label were used;
- which exchange or mileage rate was applied;
- what human confirmations or waivers occurred;
- which exact artifact was ultimately submitted.

## 4. Core objects

### 4.1 `organization_expense_reporting_contracts`

Defines one organization's reporting rules over an effective interval.

Minimum responsibilities:

- custody root (`principal_id`);
- stable contract key and display name;
- reporting body / organization label;
- reporting cadence;
- effective dates/version;
- default/base currency expectations;
- source policy provenance;
- output-template provenance and configuration;
- status (`draft`, `active`, `retired`).

The pilot contract is Camps International Mexico monthly expense reporting.

### 4.2 `organization_expense_reporting_categories`

Defines the organization's permitted expense classifications under a contract version.

Minimum fields:

- stable category key;
- canonical label;
- export label;
- policy definition;
- optional examples/notes;
- sort order and active state.

This is organization-owned operating knowledge, not a global Atlas taxonomy.

### 4.3 `organization_expense_reporting_periods`

Represents one reporting period under one contract.

Minimum fields:

- contract/version;
- period start/end;
- reporting identity shown on the artifact;
- state (`open`, `review`, `ready`, `submitted`, `reopened`);
- submitted artifact locator/hash when available;
- submission metadata and timestamps.

### 4.4 `organization_expense_reporting_rates`

Stores rates accepted for one reporting period or a narrower date window.

Examples:

- MXN -> USD adjusted exchange rate;
- mileage reimbursement per mile;
- kilometer reimbursement rate.

Each rate preserves type, units/currencies, value, source/provenance, effective date/window, and whether it was contract-provided, organization-provided, or manually confirmed.

### 4.5 `organization_expense_reporting_fact_links`

Binds a reportable source fact/evidence item to a reporting contract/period without taking ownership of the source fact.

Minimum responsibilities:

- fact kind (`expense`, `travel`, `impact_activity`);
- source authority identifier;
- immutable source reference;
- optional category classification;
- classification state/confidence;
- report-specific purpose/description when the source fact does not already provide an accepted one;
- output-shaping metadata that does not overwrite source truth.

A source fact can be linked to multiple report contracts when the real-world responsibility legitimately requires it.

### 4.6 `organization_expense_reporting_exceptions`

Represents unresolved information or human judgment required before close.

Minimum responsibilities:

- period and optional fact link;
- exception code;
- blocking/non-blocking severity;
- human-readable question;
- state (`open`, `resolved`, `waived`);
- resolution value/note;
- resolver identity and timestamp.

The exception record is first-class because the product promise is not merely generation. It is telling the human exactly what Atlas still needs.

## 5. Camps International pilot category contract

The initial pilot should preserve the supplied Camps International policy meanings for:

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

The template may render different shorthand labels. Those labels belong to export/template configuration, not to the canonical category meaning.

The current workbook also contains a `Publishing` export label. The supplied policy sheet does not independently define `Publishing`; this remains a pilot reconciliation issue and must not be silently normalized into `Printing` without Camps International authority.

## 6. CI pilot output contract

### Expense projection

Required output concepts observed in the supplied workbook:

- sequence number;
- date from/on;
- date to;
- purpose/description;
- expense type export label;
- Mexican factura indicator;
- MXN amount;
- adjusted rate;
- USD amount.

### Travel projection

Required output concepts observed in the supplied workbook:

- date from/to;
- origin;
- destination;
- purpose/description;
- vehicle/distance basis;
- odometer start/stop where applicable;
- total miles or kilometers;
- reimbursement rate;
- USD amount.

### Impact projection

Required output concepts observed in the supplied workbook:

- event;
- participants age 0–8;
- participants age 9–16;
- participants age 17+;
- total participants;
- VOICE or Other.

## 7. Application contract

Atlas application repositories must not read/write these canonical tables directly as product architecture.

The database authority should release RPC/projection seams for at least:

1. **contract retrieval** — active contract, categories, export labels, and template requirements;
2. **period retrieval** — reporting month state, rates, linked facts, and exceptions;
3. **fact admission/classification** — bind a known source fact and preserve organization-specific interpretation without rewriting the source;
4. **exception resolution** — record explicit human answer/waiver;
5. **close readiness** — deterministic evaluation of whether blocking requirements remain;
6. **export payload** — stable JSON contract from which Atlas can render the exact organization template.

The application layer may provide AI-assisted extraction/classification, but suggestions remain suggestions until the database seam accepts them under the organization's authority rules.

## 8. Pilot capture behavior

The intended David workflow is:

1. David captures or forwards evidence when reality occurs: receipt/photo/email/manual note/voice-derived structured capture.
2. Atlas links that evidence to the appropriate source fact or transitional evidence record.
3. Atlas applies the active Camps International contract and suggests category/purpose/report treatment.
4. David is interrupted only when a required fact cannot be known safely.
5. At month-end Atlas opens review with only unresolved exceptions.
6. Once blocking exceptions are resolved, Atlas produces an export payload for Expense, Travel, and Impact.
7. A template renderer generates the exact CI artifact and records its submission provenance.

## 9. First implementation tranche

This v1 tranche intentionally stops at the reporting interpretation boundary.

It may establish:

- contracts;
- categories;
- periods;
- rates;
- source-fact links;
- exceptions;
- read/projection RPCs.

It must **not** invent permanent canonical expense, travel, participant, receipt, or organization tables merely to finish this feature. Those source domains must either already exist under released authority or be designed/released separately.

## 10. Unresolved seams before production release

1. Bind contract custody to the released Atlas organization/ledger/portfolio-unit identity once that canonical seam is confirmed.
2. Confirm the canonical money/transaction source reference used for reportable expenses.
3. Confirm the canonical travel/mileage source reference.
4. Confirm the canonical activity/participant source reference.
5. Confirm receipt/factura evidence custody and durable file locator/hash contract.
6. Reconcile CI's workbook-only `Publishing` label with the supplied category policy.
7. Confirm whether `Goodwill/C/H` is only a template shorthand or intentionally combines multiple policy categories.
8. Determine authoritative rate source/approval rules for CI exchange and vehicle reimbursement.
9. Build the exact ODS/XLSX export renderer only after the stable export payload is released.

## 11. Governing test

The feature is working when David can live the month normally, capture evidence close to the moment it occurs, and reach month-end with Atlas asking only for information that could not already be known — while Camps International still receives the exact report it requires and every output row remains traceable back to real evidence and an authorized reporting rule.
