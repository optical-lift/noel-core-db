# Atlas Organization Spend — Ledger-Custodied v1

## Status

Current-main Package 5 candidate built from exact `noel-core-db/main` base:

`23d4f0041f0602cff6f428d8890a97173ca3d2a9`

Canonical migration identity for this replay:

`20260915233600_atlas_organization_spend_ledger_v1.sql`

This candidate is source-only until Database Custody CI and the protected production-schema clone both pass. Production release is a separate governed action.

## Why PR #464 is source material, not a merge candidate

PR #464 established the durable Spend distinctions correctly:

- one gross outlay occurrence is different from its purpose allocations;
- purpose allocation is different from reporting/accounting classification;
- correction and void are consequences with audit history, not silent rewrites;
- evidence supports Spend but does not become Spend merely because a receipt, OCR result, bank row, or model output exists;
- refunds/credits are not negative Spend rows;
- report-specific categories do not belong in the universal Spend kernel.

Its executable SQL is stale against current Atlas because it predates:

- Ledger as the canonical institutional custody root;
- `principal_ledger_authorities` and current Principal identity;
- current `ledger_organization_participations`;
- current evidence storage, where live `evidence_records` is Principal-scoped rather than Organization-scoped;
- Package 5 Commercial Financial Reality;
- the current migration tail `20260915224342`.

The two September 11 migration identities therefore cannot be replayed into production. Their semantics are folded into one new post-tail migration.

## Governing sequence

```text
observed outlay / receipt / card or bank evidence / human capture
        ↓
canonical Spend occurrence
        ↓
operational purpose allocation
        ↓
organization-specific reporting interpretation
        ↓
accounting handoff / provider reconciliation
```

Spend is outbound operational money truth. It is not the inverse of Commercial Payment and is not stored in the inbound commerce tables.

## Canonical custody

Every Spend occurrence carries both:

- `ledger_id` — the canonical governed reality that owns the Spend fact; and
- `organization_id` — the participating institution whose resources/purpose the Spend concerns.

The Organization must have an active `ledger_organization_participations` row in the active Ledger. Either governing or operating participation can be valid; the kernel does not reinterpret the participation kind.

This means Organization is context and participant, while Ledger is custody.

No legacy `ledgers.organization_id` shortcut is sufficient authority for new Spend truth.

## Human identity and authority

Membership and Principal answer different questions:

- `organization_membership_id` identifies the institutional relationship of a payer/recorder when that relationship is known;
- `principal_id` identifies the Atlas Principal acting through an authenticated self surface;
- `principal_has_ledger_authority_v1(...)` decides whether the first browser self APIs may govern a Ledger.

The initial browser membrane is deliberately root-Ledger only. This tranche does **not** invent an employee financial-write permission model. A future delegated work consequence may authorize employee capture without changing Spend storage.

Internal/provider adapters may use the service command membrane after they establish their own source/authority contract.

## Spend occurrence

`atlas.organization_spend_occurrences`

One row is one observed gross outlay/charge/payment occurrence. It preserves:

- Ledger + participating Organization custody;
- optional Organization Unit;
- observed/local business date (`occurred_on`);
- optional exact instant (`occurred_at`), independent of database session timezone;
- positive gross amount and currency;
- initial funding kind;
- optional payer membership;
- optional known external payee relationship plus literal payee label;
- payment method/channel;
- stable source kind/key;
- recorder Principal/membership when known;
- current truth state;
- provenance and metadata.

`occurred_on` is not derived from `occurred_at::date`. The September 11 follow-on local-date migration is incorporated from birth.

## Funding semantics

`funding_kind` remains:

- `organization`
- `organization_member`
- `external_party`
- `unresolved`

Member-funded Spend requires a same-Organization `payer_membership_id`.

Funding source does not decide reimbursement. Reimbursement remains a downstream consequence/reporting treatment.

## Purpose allocation

`atlas.organization_spend_allocations`

One occurrence may have zero, one, or many active allocations. Active allocation total cannot exceed the gross occurrence amount.

Allocation stores operational purpose and optional generic Atlas subject binding. It does not store CI category, GL account, tax code, reimbursement treatment, or QuickBooks identity.

Replacing allocations supersedes prior active rows; history is preserved.

## Current state and audit history

Current Spend state is intentionally easy to read:

- occurrence typed row = present occurrence position;
- active allocations = present purpose position;
- `organization_spend_position_v1` derives allocated/unallocated amounts.

`organization_spend_events` preserves how the current position was established or changed. Event rows are append-only.

This follows current Atlas canon: current conditions ordinarily determine present state, while history remains audit/provenance unless an explicit rule makes lineage constitutive.

## Evidence

`organization_spend_evidence_links` binds an existing `atlas.evidence_records` row to an occurrence or one allocation.

Current live Evidence is predominantly Principal-scoped. Therefore the v1 custody guard admits evidence only when its scope is structurally compatible with Spend custody:

- `ledger` scope with the same Ledger;
- `organization` scope with the same Organization; or
- `principal` scope where that Principal currently has root authority over the same Ledger.

The kernel does not rewrite Evidence scope or copy OCR/provider values into Spend authority.

Future delegated employee evidence can extend this admission rule through the delegated-authority model rather than by weakening custody.

## Source identity and retries

Canonical source identity is:

`(ledger_id, source_kind, source_key)`

Exact retry returns the existing occurrence. Reuse of the same identity with conflicting occurrence facts fails.

This allows manual capture, imports, bank/card adapters, and future provider-neutral Economic Events to converge without duplicate Spend.

## Command membrane

Direct table mutation is not an application API.

Internal/core commands:

- `record_organization_spend_core_v1(...)`
- `link_organization_spend_evidence_core_v1(...)`

Authenticated root-Ledger self APIs:

- `record_organization_spend_self_api_v1(...)`
- `replace_organization_spend_allocations_self_api_v1(...)`
- `correct_organization_spend_self_api_v1(...)`
- `void_organization_spend_self_api_v1(...)`
- `organization_spend_window_self_api_v1(...)`

The self membrane requires current Principal + active root authority for the Ledger. Organization participation is checked independently.

## Commercial Financial Reality boundary

Commercial Financial Reality remains inbound commercial/payment reality.

Spend remains outbound operational reality.

They may later reconcile through provider-neutral Economic Events, bank settlement, reimbursement, refunds/credits, or accounting handoff, but neither table family is treated as a mirror of the other.

## Refunds and credits

V1 does not encode refunds/credits as negative Spend. A returned-money fact is a separate future financial event that can reference the original Spend occurrence.

Voiding a Spend means the recorded outlay occurrence should no longer participate as active Spend truth; it does not assert that money was returned.

## Reporting boundary

PR #466 remains valid architectural source material above this kernel. Its organization-specific categories, rates, period admission, exception handling, and accounting-handoff projections must point to canonical Spend allocations and never overwrite Spend.

Reporting is replayed only after this Spend migration is released so the protected clone can validate against the real production baseline.

## Release proof required

The candidate must prove on a disposable production-schema clone that:

1. Ledger + Organization participation is required;
2. a member-funded MXN Spend can be recorded without report-specific knowledge;
3. `occurred_on` remains independent from session-timezone interpretation of `occurred_at`;
4. exact source retry is idempotent and conflicting retry fails;
5. a foreign Organization Unit, membership, payee relationship, or Evidence scope cannot cross custody;
6. one occurrence can split across multiple purpose allocations;
7. active allocations cannot exceed gross amount;
8. replacement preserves superseded allocation history;
9. correction and void append audit events;
10. direct browser/service table access is unavailable;
11. browser self APIs require root authority over the Ledger;
12. existing Commercial Financial Reality objects and Package 4 Flower writer remain unchanged.
