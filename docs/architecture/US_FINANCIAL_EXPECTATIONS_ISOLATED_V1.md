# Us — Financial Expectation and Evidence Comparison v1

Status: **structural candidate**; not a generated migration, not yet deployed.
Database custody: shared production project; logical owner of every new object is `us`.
Structural release prefix: `shared_` solely because the existing migration registry
requires a classified prefix for Us. This does not grant another product ownership
or access to Us records.

## Boundary

The candidate creates only `us` tables, functions, triggers, indexes and views.
There are NO foreign keys, joins, functions, permissions, event effects, copied
data, or required readers involving a different product schema.

Existing `us.people`, `us.employment_history` and job-search tables remain
unchanged. No additional personal identity record or second finance ledger is
created as a prerequisite.

## Financial meaning

1. `us.financial_expectation_plans`: private owner and period of the intention.
2. `us.financial_expectation_revisions`: append-only, sequential plan versions,
   with a source reference and an optional private narrative envelope. A new
   expectation makes a later revision rather than mutating the old one.
3. `us.financial_expectation_lines`: per-month, per-money-role expectations.
   `gross_inflow`, `available_inflow`, `cash_outflow`, `card_charge`,
   `card_payment`, `debt_balance`, and `capital_budget` are distinct.
   Personal, household and venture obligations cannot be silently aggregated.
4. `us.financial_observed_evidence`: source-cited, deduplicated, explicitly
   graded observations. Corrections form a supersession chain. It does NOT
   transact with or purport to synchronize a bank or card account.
5. `us.financial_expectation_actual_links`: guarded source-to-line attribution
   only when person, period, subject, currency and money role all match.
   One evidence item contributes to at most one line per revision.
6. `us.financial_expectation_comparison_v1`: private, invoker-only view.
   No evidence means unknown/NULL, not zero. Some evidence remains
   `partial_observed_coverage`. No partial variance is a full reconciliation.
   Evidence grades distinguish owner testimony from externally correlated source.

## Financial safety

- A business's gross registration or tuition is not household available cash.
- A sponsorship paid for nine months of services is not necessarily distributable
  immediately. Explicit allocations and delivery obligations stay distinct.
- Credit charges and debt balances must not be netted against household revenue.
- A repayment plan cannot consider conditional bookings or fundraising as cash.
- No personal financial payload may be placed into source, CI logs or fixtures.
- The API cannot read anything until a separately authenticated Us reader exists.

## Access

The five canonical tables have forced RLS and no `anon` or
`authenticated` grants. The only granted writer/reader is a server-side
`service_role` flow (or database owner). A future transport must authenticate
the person and enforce the owner UUID, not just trust arbitrary requested IDs.
This v1 does not install any new notebook or connected-person reader.

## Deployment and adoption

1. Review candidate and its synthetic rollback-only `postconditions.sql`.
2. Merge reviewed source to canonical main, without any real financial payload.
3. Use repo owner-triggered governed migration generator, candidate/validation paths,
   exact commit SHA, `shared` lane and `shared_us_financial_expectations_isolated_v1`.
4. Verify generated migration in a disposable, production-shaped database clone and
   run signed negative-access tests, plus existing migration custody gates.
5. Separately authorize exact protected production release.
6. Only then privately create the real personal plan and its first revision
   in Us from the already agreed 2026-11 through 2027-06 expectation, as a normal
   owner-authorized **data transaction**. Do not bake amounts into public SQL.
7. Establish subsequent financial-source ingestion into Us only after source
   identity, provider authorization and duplicate handling are verified.

The existing historical conversation is a source reference, not a dependency
on any different product schema. The current candidate has no live data backfill.
