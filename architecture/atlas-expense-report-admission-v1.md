# Atlas Expense Report Admission v1

**Status:** Candidate architecture  
**Scope:** Bind canonical organization spend allocations into an organization reporting period, preserve classification authority, create only the unresolved close questions, and expose deterministic report/accounting projections  
**Pilot:** Camps International / Mexico monthly expense reporting  
**Database authority:** `noel-core-db`

## 1. Purpose

This seam begins after Atlas already knows that money was spent.

It answers:

> Does this spend allocation belong in this reporting period, how is the organization interpreting it for this report, what still needs human judgment, and what report amount can be derived safely?

The governing chain is:

`organization spend occurrence -> spend allocation -> report admission -> organization classification -> rate/evidence checks -> close exceptions -> detail report -> category subtotal -> accounting handoff`

Report admission never rewrites the source spend.

## 2. Source authority

The preferred expense source is an effective `atlas.organization_spend_allocations` row and its parent `atlas.organization_spend_occurrences` row.

The reporting fact link should identify that source as:

- `fact_kind = expense`
- `source_authority = atlas.organization_spend_allocations`
- `source_ref = <allocation uuid>`

The source allocation owns the operational purpose and allocated source-currency amount. The parent spend occurrence owns occurrence date, source currency, payer/funding context, payee, and source provenance.

## 3. Admission and inclusion are separate from classification

A spend allocation can be a candidate for a reporting period without its organization-specific category being settled.

The report link therefore needs separate state for:

- **eligibility/inclusion** — suggested, included, excluded, unresolved;
- **category classification** — unclassified, suggested, confirmed, not applicable;
- **claim treatment** — reimbursement, organization-paid, documentation-only, donated/non-reimbursed, unresolved.

This prevents an AI category suggestion from silently becoming an authoritative reimbursement claim.

## 4. Human authority and AI assistance

AI may infer a likely category from purpose, payee, evidence, and the organization's category policy. It may also suggest whether a spend appears reportable.

AI suggestions remain `suggested`.

An authenticated organization member can explicitly confirm inclusion and/or category classification. That confirmation must preserve membership identity and timestamp.

A future organization-rule engine may confirm classifications only when a separately governed deterministic rule authorizes it. `model_suggestion` and `organization_rule` are not synonyms.

## 5. Camps International category source

The supplied Camps International policy defines 15 categories used to complement documentation of CI/CD ministry expenses presented for reimbursement. The reporting layer must preserve those meanings rather than substituting a global Atlas taxonomy.

One explicit evidence rule in the supplied policy is:

- Hospitality/Lodging accommodation expenses **must have a receipt**.

Other categories may benefit from documentation, but this policy document does not establish a universal receipt requirement for every category. The admission engine must therefore not invent one.

The workbook also contains a Mexican Factura output field. The presence of that field makes factura state reportable, but the supplied category policy does not establish that every expense requires a Mexican factura. Until CI supplies that rule, missing factura state is a report-completeness question/configuration issue, not a silently invented reimbursement rejection rule.

## 6. Rate semantics must be unambiguous

A foreign-currency reporting rate needs two layers:

1. **source quote** — the number as supplied by the organization/template/source;
2. **canonical conversion multiplier** — the value Atlas actually uses for arithmetic.

The canonical arithmetic rule is:

`reporting_amount = source_amount * conversion_multiplier`

For the observed CI workbook value `16.5`, the workbook meaning is pesos per 1 USD. Therefore:

- source amount currency: MXN;
- reporting currency: USD;
- quoted rate: `16.5`;
- quote convention: `source_units_per_one_reporting_unit`;
- canonical MXN->USD multiplier: `1 / 16.5`.

Atlas must never infer multiplication/division merely from labels such as `MXN -> USD`.

## 7. Admission command

The first product command should accept:

- report period;
- spend allocation;
- optional category suggestion/confirmation;
- optional explicit inclusion confirmation;
- optional claim treatment;
- optional reporting-purpose override;
- organization-specific report fields such as Mexican factura state;
- suggestion provenance/confidence where applicable.

It must deterministically validate:

1. caller has active membership in the report organization;
2. report period is open/review/reopened, not submitted;
3. allocation and parent spend belong to the same organization;
4. source allocation is active/effective and parent spend is not voided;
5. occurrence date falls inside the report period;
6. if the report is scoped to an organization unit, the allocation/occurrence belongs to that scope;
7. supplied category belongs to the report contract;
8. duplicate admission reuses the existing report link rather than duplicating detail.

## 8. Exception materialization

After admission, Atlas should rebuild the fact link's close exceptions from known current state.

### Blocking in v1

- `reporting_eligibility_unresolved` when inclusion is not confirmed;
- `purpose_missing` when neither source allocation purpose nor accepted reporting-purpose override exists;
- `expense_category_unresolved` when an included expense lacks a confirmed category;
- `reimbursement_treatment_unresolved` when member-funded spend has unresolved claim treatment;
- `exchange_rate_missing` when source and report currencies differ and no applicable accepted conversion rate exists;
- `exchange_rate_ambiguous` when more than one applicable accepted conversion rate exists;
- `receipt_required_missing` when a contract/category rule explicitly requires evidence and the evidence is absent;
- `category_subtotal_reconciliation_failed` when detail/report arithmetic does not reconcile.

### Warning/configuration question in the CI pilot

- `mexican_factura_state_missing` when the workbook field has not been supplied and CI has not yet established that the field is mandatory for close.

An exception must disappear or resolve when the underlying accepted state no longer warrants it. Exception materialization should therefore be deterministic/idempotent, not append endless duplicate questions.

## 9. CI conditional receipt rule

The supplied policy supports one narrow automatic rule:

If:

- confirmed category = Hospitality/Lodging; and
- the report field says the expense is an accommodation expense;

then receipt evidence is required.

If Atlas cannot establish whether a Hospitality/Lodging spend was an accommodation, it may ask that narrow question. It must not assume that every hospitality spend is lodging.

## 10. Report amount projection

For an admitted expense allocation:

- source amount = active allocation amount;
- source currency = parent spend occurrence currency;
- report currency = reporting contract base/report currency;
- if currencies are equal, report amount = source amount;
- otherwise exactly one applicable accepted conversion multiplier must exist.

The report projection should expose both the source quote and canonical multiplier so a reviewer can inspect how the conversion occurred.

For the CI workbook's quoted `16.5 MXN per 1 USD`, a `1,650 MXN` line must project to `100 USD`, not `27,225 USD`.

## 11. Category-grouped accounting projection

Only included expense links with settled report amounts can contribute to the accounting handoff.

For Camps International:

- detail remains one row per admitted spend allocation;
- primary presentation sort is category;
- within-category detail remains stable/deterministic;
- subtotal is the sum of converted USD report amounts in the category;
- Kirk's QuickBooks handoff sees one amount per category subtotal;
- the detailed report remains the supporting documentary artifact.

The projection must retain the contributing fact-link/allocation IDs behind every subtotal.

## 12. Idempotency and correction

Admission of the same allocation to the same contract/period must not duplicate it.

A later human confirmation can advance suggested state to confirmed state while retaining who confirmed it and when.

Corrections must preserve provenance. The first proof may update the reporting interpretation row because this candidate reporting layer has not yet released append-only transition authority, but canonical release should decide whether category/inclusion/claim changes require explicit interpretation events and a canonical effective-position projection.

## 13. Deliberately not included yet

- no automatic OCR implementation;
- no receipt upload/storage implementation;
- no automatic AI classifier implementation;
- no organization-wide evidence-sharing authorization change;
- no reimbursement payment lifecycle;
- no QuickBooks API call;
- no exact workbook file renderer;
- no production migration or deployment.

## 14. Acceptance proof

The rollback proof must demonstrate at least:

1. a member-funded MXN allocation is admitted once to an open monthly period;
2. AI-style category suggestion remains suggested and creates a blocking category exception;
3. explicit human confirmation clears that category exception;
4. member-funded spend with unresolved claim treatment creates a blocking treatment exception;
5. purpose inherited from the Spend allocation avoids a redundant purpose question;
6. missing foreign-currency rate blocks report amount;
7. CI's `16.5 MXN per USD` quote is normalized to a `1/16.5` multiplier;
8. `1,650 MXN` converts to `100 USD`;
9. two confirmed Facilities lines group into one Facilities subtotal while source lines remain separate;
10. duplicate admission is idempotent;
11. conditional lodging receipt enforcement only fires when the contract condition is actually established;
12. all proof objects and fixture rows disappear on rollback.

## 15. Migration custody

This is development/proof work only. Production migration identity, RLS release, evidence-sharing changes, deployment, and downstream accounting integration remain separate authorities. The branch is currently behind concurrent `main` work and must be reconciled before canonical migration materialization.
