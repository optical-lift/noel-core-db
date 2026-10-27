# Us financial expectations v1 — source candidate

Status: structural candidate only, **not a production migration or live feature**.
Release owner: Shared (Us personal custody reads only approved Atlas canonical actuals).
Production source authority: `optical-lift/noel-core-db`.

## Why this exists

A household or founder may have a financial intention across personal and separately
governed organizations. It is not an accounting journal. Expected receipts, cash
obligations, capital projects, credit-card borrowing and gross institutional sales
must retain their different meanings. The existing canonical sources continue to
own actual payments and Spend.

## Contracts

- `us.financial_expectation_plans`: immutable identity scoped to exactly one auth
  person. Source evidence must be person-scoped `atlas.evidence_records` with
  `subject_domain='personal_finance'`. A source belonging to another person is rejected.
- `us.financial_expectation_revisions`: append-only successive versions referencing
  person-owned source evidence; version insert sequence is serialized.
- `us.financial_expectation_month_lines`: immutable forecast lines for one calendar
  month, one defined money role, expectation status, currency, and economic scope.
  Institutional gross receipts are not personal free cash; card charges are not
  debt payments; capital budgets are not earned revenue.
- `us.financial_expectation_actual_links`: verified pointers to canonical Atlas
  commercial receipts or confirmed organization Spend. No duplicate actual amounts
  or bank transactions are stored. One source can contribute to no more than one
  line within a forecast revision. A link requires an **actual source** whose month,
  currency, organization and direction match the destination line, plus active
  owner membership or active root governing authority over the organization.
- `us.financial_expectation_month_comparison_v1`: service-only invoker view.
  No verified source -> NULL actual and `no_verified_actual_coverage`;
  some verified sources -> `partial_verified_source_coverage`. A partial
  variance is **not** a completed forecast variance. Revisions remain independently
  queryable; the caller chooses the authoritative latest adopted revision.

## Authorization

Everything is closed to `PUBLIC`, `anon` and `authenticated`.
Canonical tables have forced RLS. Only `service_role` can select or append.
There is no direct client or guessed "connected person" entitlement. The
receiving application must independently authenticate the owner and prevent
any cross-person data from reaching the requester. The actual-source guard
does not grant the user ownership of any source object.

The project has an ongoing unified permission/disclosure review; do not
publish a new notebook reader before its signed negative-access tests pass.

## Known boundaries

1. The personal bank connection in Finances is not present as canonical transactions
   in the shared Supabase project. Do **not** imply that forecasts are reconciled to
   personal bank statements or that a $0 actual means no transaction occurred.
2. Atlas organization income and Spend can be linked only when genuine source rows
   exist and organizational owner scope can be verified. Cross-company cash
   allocations and instructor payouts need separate canonical evidence.
3. University prepaid tuition must not silently be labeled earned or available
   personal cash. Explicit revenue recognition and custody distribution remain
   downstream contracts.
4. No forecast source, financing amount, person name, bank account, or transaction
   from real life may be committed to this public repository or a public fixture.
5. No future automated ingestion may create duplicate historical financial facts;
   source identity keys and source-ledger reconciliation must be governed.

## Validation gates

- Candidate and `postconditions.sql` contain structural SQL plus synthetic,
  transactional, rolled-back negative tests only.
- Source generation uses the repository owner-triggered migration generator.
- Run production-shaped clone, exact source custody checks, signed negative
  access tests for all personal and organizational access pathways.
- Merge generated migration to `main` only after checks; production release
  requires separate protected authorization with the exact version and project.
- **Only after** release, adopt the existing private person-scoped financial
  expectation evidence into the new plan/revision/month-lines storage through
  an authorized private data transaction. Keep all private numeric values
  out of GitHub.
