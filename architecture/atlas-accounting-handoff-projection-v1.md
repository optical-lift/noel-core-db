# Atlas Accounting Handoff Projection v1

**Status:** Candidate architecture  
**Scope:** Software-neutral bridge from detailed Atlas/reporting facts to summarized accounting entry requirements  
**Pilot:** Camps International treasurer workflow into QuickBooks  
**Database authority:** `noel-core-db`

## 1. Purpose

Many organizations keep operational or reimbursement detail at a finer grain than their accounting system needs for final entry.

Atlas must not force a choice between those two grains.

The governing flow is:

`detailed source facts -> organization reporting classification -> grouped detail report -> category subtotals -> accounting handoff -> documentary artifact`

The accounting handoff is a **projection**, not a replacement for the source facts and not a second accounting ledger.

## 2. Pilot requirement established September 10, 2026

For Camps International, David Caldwell clarified the intended treasurer workflow:

- expense categories may occur repeatedly throughout a monthly report;
- the final expense report should be grouped/sorted by **category**, not by date or amount;
- each category should have a subtotal;
- the treasurer, Kirk, should only need to enter the one category subtotal into QuickBooks rather than re-enter every detailed expense line;
- the detailed expense report remains intact and is uploaded into QuickBooks as documentary proof/supporting documentation.

Therefore Atlas must generate both the detailed evidentiary schedule and the summarized accounting handoff from the same accepted facts.

## 3. Governing rules

### 3.1 Never collapse source detail

Category aggregation happens only in a projection.

If five Facilities expenses total to one Facilities subtotal, Atlas still retains all five underlying expense facts, their receipts/evidence, dates, purposes, amounts, classifications, and provenance.

The accounting system may receive one number; Atlas must still be able to show exactly what made up that number.

### 3.2 Aggregation is organization-defined

The grouping key is not globally hard-coded as `expense category`.

A reporting/accounting contract defines the aggregation dimensions required by the organization or downstream accounting workflow.

Possible grouping dimensions include:

- reporting category;
- accounting account/code;
- department or organization unit;
- project/program;
- funding source;
- tax treatment;
- currency;
- reimbursement class;
- another organization-defined dimension.

The Camps International pilot uses **expense category** as the required grouping dimension.

### 3.3 Presentation sort is separate from fact chronology

The final report presentation may be sorted for the downstream workflow without changing fact chronology.

For Camps International:

- primary/final expense presentation sort: category;
- date and amount remain line attributes;
- date or amount must not break category grouping;
- within-category line ordering may remain stable according to the report's configured secondary order.

### 3.4 Subtotals are reconciliation units

Every generated subtotal must be deterministically traceable to the exact detail lines included in it.

At minimum, the export/handoff payload must satisfy:

`sum(detail lines in group) = group subtotal`

and

`sum(all group subtotals) = report expense total`

Any mismatch is a blocking close exception, not something the renderer silently repairs.

### 3.5 Accounting destination is an adapter

QuickBooks is the Camps International pilot destination. It is not part of the universal data model.

The same projection should be usable for QuickBooks, Xero, Sage, NetSuite, an internal ERP, a bookkeeper's spreadsheet, or a manual accounting workflow.

The organization contract may specify:

- downstream system label;
- posting grain;
- grouping dimensions;
- amount/currency field to post;
- account/category mapping when known;
- documentary artifact requirement;
- posting instructions;
- whether posting remains manual or is later automated through an adapter.

### 3.6 Named people are instances, roles are structure

Kirk is the current Camps International treasurer/operator for this workflow. The reusable model should store the responsible organization role/membership relationship rather than making `Kirk` part of schema semantics.

### 3.7 Documentary proof remains attached to the summarized posting

When the downstream accounting workflow accepts supporting documentation, Atlas should preserve the relationship between:

- the summarized category amount posted downstream;
- the detail report artifact used as documentary proof;
- the report period and contract version;
- the detail facts composing that subtotal.

A future direct QuickBooks adapter may transmit the artifact automatically, but the v1 architecture must also support the current manual upload workflow.

## 4. Projection contract

A stable accounting handoff projection should be capable of returning at least:

### `detailGroups`

One group per configured aggregation key, containing:

- grouping key/value;
- display/export label;
- stable included line references;
- line count;
- subtotal amount;
- currency;
- any organization/account mapping known for the group.

### `accountingSummary`

The minimal set of numbers the downstream accounting operator needs to enter.

For the CI pilot this is one summary line per expense category.

### `reconciliation`

- detail-line total;
- subtotal total;
- overall report total;
- reconciliation state;
- any blocking discrepancy.

### `documentaryArtifact`

When generated/submitted:

- artifact locator;
- immutable hash where available;
- artifact kind/version;
- relationship to the report period;
- downstream attachment/posting evidence when known.

## 5. Camps International pilot configuration

The CI contract should express:

- `expense.primarySort = category`;
- `expense.groupBy = category`;
- `expense.showCategorySubtotal = true`;
- `accountingHandoff.destinationSystem = QuickBooks`;
- `accountingHandoff.postingGrain = category_subtotal`;
- `accountingHandoff.retainDetailedReport = true`;
- `accountingHandoff.documentaryProof = full_expense_report`;
- `accountingHandoff.operatorRole = treasurer`.

The exact QuickBooks transaction form, account/code mapping, posting date convention, and whether the treasurer posts one multi-line transaction or multiple transactions remain implementation details until Camps International confirms them.

## 6. Relationship to Organization Expense Reporting

`Atlas Organization Expense Reporting v1` owns the reporting contract, categories, period, interpretations, exceptions, and export provenance.

This Accounting Handoff Projection consumes that accepted reporting state and produces the accounting-ready summary without claiming ownership of expense truth.

It therefore belongs **after** reporting classification and **before** downstream accounting entry.

## 7. No new canonical accounting table yet

This requirement does not justify inventing a new universal accounting ledger before Atlas has a released money/expense fact model.

For the first CI tranche, grouping/sort/subtotal/documentary-proof rules can be represented in the reporting contract's configuration and exposed through a stable projection payload.

A first-class handoff/posting event table should be added only when Atlas needs to persist facts such as:

- a posting was actually entered downstream;
- a downstream transaction identifier exists;
- an artifact was attached;
- a posting was rejected/reversed/reconciled.

Those are downstream interaction facts, distinct from the subtotal calculation itself.

## 8. Governing test

Given a month containing repeated expenses in the same Camps International category, Atlas should be able to produce a category-grouped detail report with correct subtotals, give the treasurer only one accounting amount per category to enter, preserve every underlying detail line and receipt, and preserve the full report as the documentary proof supporting the summarized accounting entry.
